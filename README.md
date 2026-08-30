# Laptop Audio Bridge

Stream all Windows system audio to Safari on an iPhone over the same Wi-Fi network. Audio never leaves your local network.

## Start it

1. Make sure the laptop and iPhone are on the same Wi-Fi network. Avoid a guest network, which may isolate devices.
2. Right-click `start.ps1`, choose **Run with PowerShell**, and allow Python through Windows Firewall on **Private networks** if Windows asks.
3. The PowerShell window prints an address such as `http://192.168.1.20:8000`. Open that exact address in Safari on the iPhone.
4. Tap **Start listening**. iOS requires this tap before a webpage may play sound.
5. Start a video, call, or song on the laptop. You can turn the laptop speaker volume down, but do not mute Windows or the source app—the loopback stream follows that output.

Stop the bridge with **Ctrl+C** in PowerShell.

## Troubleshooting

- **No address opens:** set the current Wi-Fi network to **Private** in Windows, allow Python through the firewall, and verify both devices are on the same non-guest Wi-Fi.
- **Connected but silent:** select the same Windows output device your apps use. List devices with:

  ```powershell
  .\.venv\Scripts\python.exe app.py --list-devices
  ```

  Then start with part of the desired name:

  ```powershell
  .\.venv\Scripts\python.exe app.py --device "Headphones"
  ```

- **Audio stops when the screen locks:** keep Safari open and prevent the iPhone from auto-locking while listening. iOS may suspend browser audio in the background.
- **Audio stops when the screen locks:** recent iOS versions receive a background-playback hint from the page, but Safari can still suspend local Web Audio or its WebSocket on some iPhone/iOS combinations. Keep Safari in the foreground for guaranteed playback; reliable background playback requires a native iPhone app with the audio background mode.
- **Delay or dropouts:** use 5 GHz Wi-Fi, stay near the router, close other tabs, and avoid power-saving mode.
- **Feedback/echo:** use headphones on the iPhone or turn the laptop's physical speaker down.

## How it works

The Python service captures native 16-bit stereo PCM from the default Windows output using a low-latency WASAPI loopback stream and sends short 10 ms chunks over a WebSocket. The webpage maintains a small adaptive live buffer and plays the stream with the Web Audio API. Old chunks are dropped if the phone falls behind so delay does not grow indefinitely.

This MVP prioritizes a simple local setup and broad iPhone Safari compatibility. Uncompressed stereo uses about 1.5 Mbit/s, which is small for normal Wi-Fi.

On a strong 5 GHz connection, typical end-to-end latency is roughly 60–150 ms. Exact results depend on the Windows audio driver and the iPhone's Safari audio-output buffer; truly zero-latency browser audio is not possible.
