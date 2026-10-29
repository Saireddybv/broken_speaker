from __future__ import annotations

import argparse
import asyncio
import contextlib
import json
import logging
import socket
import threading
import uuid
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import pyaudiowpatch as pyaudio
import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles


ROOT = Path(__file__).resolve().parent
STATIC_DIR = ROOT / "static"
LOG = logging.getLogger("audio_bridge")


@dataclass(frozen=True)
class AudioConfig:
    sample_rate: int = 48_000
    channels: int = 2
    block_frames: int = 480  # 10 ms at 48 kHz for lower capture latency


class AudioBridge:
    """Capture Windows WASAPI loopback audio and fan it out to browser clients."""

    def __init__(self, config: AudioConfig, device_query: str | None = None) -> None:
        self.config = config
        self.device_query = device_query
        self._clients: dict[str, tuple[asyncio.AbstractEventLoop, asyncio.Queue[bytes]]] = {}
        self._clients_lock = threading.Lock()
        self._wake_capture = threading.Event()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self.device_name = "Not connected"
        self.last_error: str | None = None
        self.frames_sent = 0

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._capture_loop, name="wasapi-loopback", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self._wake_capture.set()
        if self._thread:
            self._thread.join(timeout=3)

    def add_client(self, loop: asyncio.AbstractEventLoop) -> tuple[str, asyncio.Queue[bytes]]:
        client_id = uuid.uuid4().hex
        # Cap pending data at about 120 ms. Dropping an old packet is preferable
        # to allowing lip-sync delay to grow after a brief network stall.
        queue: asyncio.Queue[bytes] = asyncio.Queue(maxsize=12)
        with self._clients_lock:
            self._clients[client_id] = (loop, queue)
        self._wake_capture.set()
        return client_id, queue

    def remove_client(self, client_id: str) -> None:
        with self._clients_lock:
            self._clients.pop(client_id, None)
            if not self._clients:
                self._wake_capture.clear()

    @property
    def client_count(self) -> int:
        with self._clients_lock:
            return len(self._clients)

    def status(self) -> dict[str, Any]:
        return {
            "device": self.device_name,
            "clients": self.client_count,
            "capturing": self.client_count > 0 and self.last_error is None,
            "error": self.last_error,
            "sampleRate": self.config.sample_rate,
            "channels": self.config.channels,
        }

    def _select_loopback(self, audio: pyaudio.PyAudio) -> dict[str, Any]:
        host = audio.get_host_api_info_by_type(pyaudio.paWASAPI)
        default_output = audio.get_device_info_by_index(host["defaultOutputDevice"])
        devices = list(audio.get_loopback_device_info_generator())
        return choose_loopback(devices, str(default_output["name"]), self.device_query)

    def _capture_loop(self) -> None:
        while not self._stop.is_set():
            if self.client_count == 0:
                self.device_name = "Waiting for a listener"
                self._wake_capture.wait(timeout=0.5)
                continue

            audio: pyaudio.PyAudio | None = None
            try:
                audio = pyaudio.PyAudio()
                device = self._select_loopback(audio)
                self.device_name = str(device["name"])
                self.last_error = None
                LOG.info("Capturing system audio from %s", self.device_name)
                stream = audio.open(
                    format=pyaudio.paInt16,
                    channels=self.config.channels,
                    rate=self.config.sample_rate,
                    input=True,
                    input_device_index=int(device["index"]),
                    frames_per_buffer=self.config.block_frames,
                )
                try:
                    while self.client_count and not self._stop.is_set():
                        packet = stream.read(self.config.block_frames, exception_on_overflow=False)
                        self._publish(packet)
                finally:
                    stream.stop_stream()
                    stream.close()
            except Exception as exc:  # Hardware and driver errors need retries.
                self.last_error = str(exc)
                self.device_name = "Capture unavailable"
                LOG.exception("Audio capture failed")
                self._publish_error(str(exc))
                self._stop.wait(2)
            finally:
                if audio is not None:
                    audio.terminate()

    def _publish(self, packet: bytes) -> None:
        with self._clients_lock:
            clients = list(self._clients.values())
        for loop, queue in clients:
            with contextlib.suppress(RuntimeError):
                loop.call_soon_threadsafe(offer_latest, queue, packet)
        self.frames_sent += self.config.block_frames

    def _publish_error(self, message: str) -> None:
        packet = json.dumps({"type": "error", "message": message}).encode("utf-8")
        with self._clients_lock:
            clients = list(self._clients.values())
        for loop, queue in clients:
            with contextlib.suppress(RuntimeError):
                loop.call_soon_threadsafe(offer_latest, queue, packet)


def choose_loopback(
    devices: list[dict[str, Any]], default_output_name: str, query: str | None = None
) -> dict[str, Any]:
    """Choose an explicit match, otherwise the loopback for Windows' default output."""
    if not devices:
        raise RuntimeError("No Windows WASAPI loopback audio device was found.")
    if query:
        matches = [device for device in devices if query.casefold() in str(device["name"]).casefold()]
        if not matches:
            names = ", ".join(str(device["name"]) for device in devices)
            raise RuntimeError(f'No loopback device matched "{query}". Available: {names}')
        return matches[0]

    matches = [
        device
        for device in devices
        if default_output_name.casefold() in str(device["name"]).casefold()
    ]
    return matches[0] if matches else devices[0]


def offer_latest(queue: asyncio.Queue[bytes], packet: bytes) -> None:
    """Keep real-time audio current instead of accumulating seconds of latency."""
    if queue.full():
        with contextlib.suppress(asyncio.QueueEmpty):
            queue.get_nowait()
    with contextlib.suppress(asyncio.QueueFull):
        queue.put_nowait(packet)


CONFIG = AudioConfig()
bridge = AudioBridge(CONFIG)


@contextlib.asynccontextmanager
async def lifespan(_: FastAPI):
    bridge.start()
    yield
    bridge.stop()


app = FastAPI(title="Laptop Audio Bridge", lifespan=lifespan)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.get("/", include_in_schema=False)
async def home() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/status", include_in_schema=False)
async def status() -> JSONResponse:
    return JSONResponse(bridge.status())


@app.get("/health", include_in_schema=False)
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.websocket("/ws/audio")
async def audio_socket(websocket: WebSocket) -> None:
    await websocket.accept()
    loop = asyncio.get_running_loop()
    client_id, queue = bridge.add_client(loop)
    await websocket.send_json({"type": "config", **asdict(CONFIG), "device": bridge.device_name})
    try:
        while True:
            packet = await queue.get()
            if packet.startswith(b'{"type": "error"'):
                await websocket.send_text(packet.decode("utf-8"))
            else:
                await websocket.send_bytes(packet)
    except (WebSocketDisconnect, RuntimeError):
        pass
    finally:
        bridge.remove_client(client_id)


def local_ip() -> str:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("1.1.1.1", 80))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Stream Windows system audio to a phone browser.")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--device", help="Part of the Windows output-device name to capture")
    parser.add_argument("--list-devices", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.list_devices:
        audio = pyaudio.PyAudio()
        try:
            print("Windows loopback devices:")
            for device in audio.get_loopback_device_info_generator():
                print(f"  - {device['name']}")
        finally:
            audio.terminate()
        raise SystemExit(0)
    bridge.device_query = args.device
    print(f"\nOpen this on your iPhone (same Wi-Fi): http://{local_ip()}:{args.port}\n")
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()
