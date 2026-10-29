"""Integration check against a running local bridge (includes a short test tone)."""
import asyncio
import json
import struct
import sys
import urllib.request
import winsound

import websockets


async def main():
    origin = sys.argv[1].rstrip('/')
    for path in ('/', '/static/player.js', '/static/styles.css', '/health'):
        with urllib.request.urlopen(origin + path, timeout=5) as response:
            assert response.status == 200, path
    async with websockets.connect(origin.replace('http:', 'ws:') + '/ws/audio') as ws:
        config = json.loads(await asyncio.wait_for(ws.recv(), 5))
        tone = asyncio.create_task(asyncio.to_thread(winsound.Beep, 660, 1500))
        peak = 0
        for _ in range(40):
            packet = await asyncio.wait_for(ws.recv(), 5)
            assert isinstance(packet, bytes), packet
            assert len(packet) == config['block_frames'] * config['channels'] * 2
            peak = max(peak, max(abs(x[0]) for x in struct.iter_unpack('<h', packet)))
        await tone
        assert peak > 0, 'Captured only silence during the test tone'
    print('LAN page, player assets, WebSocket config and 40 non-silent PCM packets verified.')


asyncio.run(main())
