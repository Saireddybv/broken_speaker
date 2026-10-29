# Broken Speaker

**Laptop speakers broken? Use your iPhone as the speaker.**

Broken Speaker streams all of your Windows laptop's sound (videos, calls, music, games) to Safari on your iPhone over your home Wi-Fi. You don't need an app on the phone, an account or an internet connection. The audio never leaves your local network.

[![Tests](https://github.com/Saireddybv/broken_speaker/actions/workflows/tests.yml/badge.svg)](https://github.com/Saireddybv/broken_speaker/actions/workflows/tests.yml)
![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## What you need

- A Windows 10 or 11 laptop
- [Python 3.11 or newer](https://www.python.org/downloads/windows/) (keep **"py launcher"** ticked in the installer)
- An iPhone (or any phone with a modern browser) on the **same Wi-Fi** as the laptop. Guest networks often block devices from seeing each other.

## Quick start (2 minutes)

1. **Download** this project: click the green **Code** button, choose **Download ZIP** and unzip it. Or run:
   ```bash
   git clone https://github.com/Saireddybv/broken_speaker.git
   ```
2. **Double-click `Start Broken Speaker.bat`.** The first run installs everything it needs, which takes about a minute. If Windows Firewall asks, allow Python on **Private networks**.
3. The window prints an address such as `http://192.168.1.20:8000`. **Open that address in Safari on your iPhone** and tap **Start listening**.

Play something on the laptop and it comes out of your phone. To stop, press **Ctrl+C** in the window or close it.

> Tip: you can turn the laptop volume down, but don't **mute** Windows or the app that's playing. The stream copies whatever Windows is outputting.

## Optional: tray app (no terminal window)

Double-click **`Install Tray App.bat`** once. It creates a **Broken Speaker** shortcut on your Desktop. Opening it puts an icon in the notification area by the clock (it may be hidden under the **^** arrow).

- Click the icon, choose **Start streaming**, then scan the **QR code** with your iPhone camera.
- **Stop** shuts the server down. Right-click the icon and choose **Quit** to exit completely.
- **Launch tray at sign-in** starts only the tray icon at login. Streaming stays off until you start it.
- If port 8000 is busy, it picks a free port up to 8010, so always use the link it shows.
- Logs are stored in `%LOCALAPPDATA%\BrokenSpeaker`.

## Options

Pass these to `Start Broken Speaker.bat` from a terminal, or to `app.py` directly:

| Option | What it does |
| --- | --- |
| `--list-devices` | Lists the Windows audio outputs you can capture |
| `--device "Headphones"` | Captures a specific output (matches part of its name) |
| `--port 8001` | Uses a different port |

Example:

```powershell
.\.venv\Scripts\python.exe app.py --list-devices
.\.venv\Scripts\python.exe app.py --device "Headphones"
```

## Troubleshooting

| Problem | Fix |
| --- | --- |
| **The address won't open on the phone** | In Windows Wi-Fi settings, set the network to **Private**. Allow Python through the firewall. Make sure both devices are on the same non-guest Wi-Fi. |
| **"Python was not found"** | Install Python from python.org with the **py launcher** option, then run the `.bat` again. |
| **Connected but silent** | You're capturing the wrong output. Run with `--list-devices`, then start with `--device "<part of the name>"`. Check that Windows isn't muted. |
| **Audio stops when the iPhone locks** | Keep Safari open in the foreground and turn off Auto-Lock while listening. iOS may pause browser audio in the background. |
| **Delay or dropouts** | Use 5 GHz Wi-Fi, stay near the router, close other Safari tabs and turn off Low Power Mode. |
| **Echo or feedback** | Use headphones on the phone or turn the laptop's physical speaker down. |
| **Double-clicking the `.bat` does nothing** | Right-click `start.ps1` and choose **Run with PowerShell** to see the error. |

## How it works

```
Windows audio ──WASAPI loopback──► app.py (FastAPI) ──WebSocket, 10 ms PCM chunks──► Safari (Web Audio API)
```

The Python service captures 16-bit stereo PCM at 48 kHz from your default Windows output using a low-latency WASAPI loopback stream. It sends 10 ms chunks over a WebSocket. The web page keeps a small adaptive buffer and plays the stream with the Web Audio API. If the phone falls behind, old chunks are dropped so the delay doesn't keep growing.

- **Latency:** roughly 60–150 ms on strong 5 GHz Wi-Fi. This depends on the audio driver and Safari's output buffer. Zero-latency browser audio isn't possible.
- **Bandwidth:** uncompressed stereo uses about 1.5 Mbit/s, which is small for normal Wi-Fi.
- **Privacy:** there are no accounts and no cloud, and nothing is sent outside your network. The QR code is generated locally.
- **Security:** there is no password. Anyone on the same Wi-Fi who opens the address can listen, so use it only on networks you trust and never forward the port to the internet.

## Development

```powershell
py -3 -m venv .venv
.venv\Scripts\python -m pip install -r requirements-dev.txt
.venv\Scripts\python -m pytest
.venv\Scripts\python app.py
```

`verify-flow.py http://127.0.0.1:8000` runs an end-to-end check against a running server. It plays a short test tone and confirms that real audio packets arrive.

| File | Purpose |
| --- | --- |
| `app.py` | Audio capture and web server |
| `static/` | iPhone player page |
| `tray.ps1`, `setup-tray.ps1` | Windows tray controller and installer |
| `make-qr.py`, `make-icon.ps1` | Local QR code and icon generation |
| `tests/` | Unit tests |

Issues and pull requests are welcome.

## Related

Broken Speaker is also included as the **Audio** tool in [Local First](https://github.com/Saireddybv/local_first). That project combines file transfer, a shared clipboard and audio in one app.

## License

[MIT](LICENSE)
