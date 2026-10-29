import asyncio

import pytest

from broken_speaker.app import choose_loopback, offer_latest


def test_choose_loopback_prefers_default_output() -> None:
    devices = [
        {"index": 1, "name": "HDMI Output [Loopback]"},
        {"index": 2, "name": "Speakers (Realtek) [Loopback]"},
    ]
    assert choose_loopback(devices, "Speakers (Realtek)")["index"] == 2


def test_choose_loopback_honors_explicit_query() -> None:
    devices = [
        {"index": 1, "name": "HDMI Output [Loopback]"},
        {"index": 2, "name": "Speakers (Realtek) [Loopback]"},
    ]
    assert choose_loopback(devices, "Speakers (Realtek)", "HDMI")["index"] == 1
    with pytest.raises(RuntimeError, match="No loopback device matched"):
        choose_loopback(devices, "Speakers (Realtek)", "Bluetooth")


def test_offer_latest_drops_oldest_packet() -> None:
    queue: asyncio.Queue[bytes] = asyncio.Queue(maxsize=2)
    queue.put_nowait(b"old")
    queue.put_nowait(b"middle")
    offer_latest(queue, b"new")
    assert queue.get_nowait() == b"middle"
    assert queue.get_nowait() == b"new"
