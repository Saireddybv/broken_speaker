(() => {
  "use strict";

  const button = document.querySelector("#listen-button");
  const buttonLabel = button.querySelector("span");
  const statusText = document.querySelector("#status-text");
  const statusDot = document.querySelector("#status-dot");
  const deviceName = document.querySelector("#device-name");
  const volume = document.querySelector("#volume");
  const volumeLabel = document.querySelector("#volume-label");
  const bufferLabel = document.querySelector("#buffer-label");
  const canvas = document.querySelector("#meter");
  const canvasContext = canvas.getContext("2d");

  let socket = null;
  let context = null;
  let processor = null;
  let gain = null;
  let channels = 2;
  let sourceSampleRate = 48000;
  let queues = [[], []];
  let queuedFrames = 0;
  let primed = false;
  let targetBufferMs = 30;
  let stableCallbacks = 0;
  let running = false;
  let level = 0;
  let animationId = null;

  function setStatus(text, state = "") {
    statusText.textContent = text;
    statusDot.className = `status-dot ${state}`;
  }

  function resetQueue() {
    queues = Array.from({ length: channels }, () => []);
    queuedFrames = 0;
    primed = false;
    targetBufferMs = 30;
    stableCallbacks = 0;
  }

  function enqueuePcm(arrayBuffer) {
    const pcm = new Int16Array(arrayBuffer);
    const frames = Math.floor(pcm.length / channels);
    const channelData = Array.from({ length: channels }, () => new Float32Array(frames));
    let peak = 0;
    for (let frame = 0; frame < frames; frame += 1) {
      for (let channel = 0; channel < channels; channel += 1) {
        const sample = pcm[frame * channels + channel] / 32768;
        channelData[channel][frame] = sample;
        peak = Math.max(peak, Math.abs(sample));
      }
    }
    channelData.forEach((data, index) => queues[index].push({ data, offset: 0 }));
    queuedFrames += frames;
    level = Math.max(level * 0.72, peak);

    // If the phone stalls, discard old sound and return to live audio.
    const maxFrames = sourceSampleRate * Math.max(0.18, (targetBufferMs + 60) / 1000);
    while (queuedFrames > maxFrames && queues[0].length > 1) {
      const dropped = queues[0][0].data.length - queues[0][0].offset;
      queues.forEach((queue) => queue.shift());
      queuedFrames -= dropped;
    }
  }

  function fillOutput(event) {
    const frameCount = event.outputBuffer.length;
    // Start low, then grow the jitter target only when this particular phone
    // underruns. After a stable period it slowly returns toward low latency.
    const targetFrames = sourceSampleRate * (targetBufferMs / 1000);
    let fadeIn = false;
    if (!primed && queuedFrames >= targetFrames) {
      primed = true;
      fadeIn = true;
    }
    if (!primed) {
      for (let channel = 0; channel < event.outputBuffer.numberOfChannels; channel += 1) {
        event.outputBuffer.getChannelData(channel).fill(0);
      }
      bufferLabel.textContent = "buffering";
      return;
    }

    const availableBeforeRender = queuedFrames;
    for (let channel = 0; channel < event.outputBuffer.numberOfChannels; channel += 1) {
      const output = event.outputBuffer.getChannelData(channel);
      output.fill(0);
      let written = 0;
      const queue = queues[Math.min(channel, queues.length - 1)];
      while (written < frameCount && queue.length) {
        const chunk = queue[0];
        const available = chunk.data.length - chunk.offset;
        const amount = Math.min(available, frameCount - written);
        output.set(chunk.data.subarray(chunk.offset, chunk.offset + amount), written);
        chunk.offset += amount;
        written += amount;
        if (chunk.offset >= chunk.data.length) queue.shift();
      }

      // Short fades hide the hard discontinuity that otherwise sounds like a
      // click or buzz when iOS pauses a callback for too long.
      const fadeFrames = Math.min(96, written);
      if (fadeIn) {
        for (let index = 0; index < fadeFrames; index += 1) {
          output[index] *= index / fadeFrames;
        }
      }
      if (availableBeforeRender < frameCount && fadeFrames) {
        for (let index = 0; index < fadeFrames; index += 1) {
          output[written - fadeFrames + index] *= 1 - index / fadeFrames;
        }
      }
    }
    queuedFrames = Math.max(0, queuedFrames - frameCount);
    if (availableBeforeRender < frameCount) {
      primed = false;
      stableCallbacks = 0;
      targetBufferMs = Math.min(80, targetBufferMs + 10);
    } else {
      stableCallbacks += 1;
      if (stableCallbacks >= 1400 && targetBufferMs > 30) {
        targetBufferMs = Math.max(30, targetBufferMs - 5);
        stableCallbacks = 0;
      }
    }
    bufferLabel.textContent = queuedFrames ? `${Math.round((queuedFrames / sourceSampleRate) * 1000)} ms` : "buffering";
  }

  async function startAudio(config) {
    channels = config.channels || 2;
    sourceSampleRate = config.sample_rate || 48000;
    resetQueue();
    // Modern iOS uses this hint to keep Web Audio in the media-playback
    // category when Safari is backgrounded or the screen locks.
    if ("audioSession" in navigator) {
      try { navigator.audioSession.type = "playback"; } catch (_) { /* Older Safari. */ }
    }
    context = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: sourceSampleRate });
    await context.resume();
    gain = context.createGain();
    gain.gain.value = Number(volume.value);
    // ScriptProcessor has broad iOS Safari support and works on local HTTP pages.
    // 1024 frames is about 21 ms at 48 kHz. It is the lowest consistently
    // stable ScriptProcessor size across recent iPhones on local HTTP pages.
    processor = context.createScriptProcessor(1024, 0, channels);
    processor.onaudioprocess = fillOutput;
    processor.connect(gain).connect(context.destination);
  }

  async function connect() {
    running = true;
    button.disabled = true;
    setStatus("Connecting…");
    const scheme = location.protocol === "https:" ? "wss" : "ws";
    socket = new WebSocket(`${scheme}://${location.host}/ws/audio`);
    socket.binaryType = "arraybuffer";

    socket.onmessage = async (event) => {
      if (typeof event.data === "string") {
        const message = JSON.parse(event.data);
        if (message.type === "config") {
          try {
            await startAudio(message);
            deviceName.textContent = message.device || "Windows system audio";
            setStatus("Listening live", "live");
            button.disabled = false;
            button.classList.add("stop");
            buttonLabel.textContent = "Stop listening";
          } catch (error) {
            fail(`Audio could not start: ${error.message}`);
          }
        } else if (message.type === "error") {
          fail(message.message);
        }
      } else if (context) {
        enqueuePcm(event.data);
      }
    };
    socket.onerror = () => fail("Could not reach the laptop");
    socket.onclose = () => {
      if (running) fail("Connection closed — tap to retry");
    };
  }

  function fail(message) {
    setStatus(message, "error");
    stop(false);
  }

  function stop(showReady = true) {
    running = false;
    if (socket) {
      socket.onclose = null;
      socket.close();
      socket = null;
    }
    if (processor) processor.disconnect();
    if (gain) gain.disconnect();
    if (context) context.close();
    context = processor = gain = null;
    resetQueue();
    button.disabled = false;
    button.classList.remove("stop");
    buttonLabel.textContent = "Start listening";
    bufferLabel.textContent = "—";
    if (showReady) setStatus("Ready to connect");
  }

  function drawMeter() {
    const width = canvas.width;
    const height = canvas.height;
    canvasContext.clearRect(0, 0, width, height);
    canvasContext.strokeStyle = "rgba(125, 255, 173, .14)";
    canvasContext.lineWidth = 2;
    canvasContext.beginPath();
    canvasContext.moveTo(0, height / 2);
    canvasContext.lineTo(width, height / 2);
    canvasContext.stroke();

    canvasContext.strokeStyle = running ? "#7dffad" : "#496256";
    canvasContext.lineWidth = 4;
    canvasContext.lineCap = "round";
    canvasContext.beginPath();
    const amplitude = Math.max(2, level * height * 0.45);
    for (let x = 0; x <= width; x += 6) {
      const envelope = Math.sin((x / width) * Math.PI);
      const y = height / 2 + Math.sin(x * 0.115 + performance.now() * 0.004) * amplitude * envelope;
      if (x === 0) canvasContext.moveTo(x, y); else canvasContext.lineTo(x, y);
    }
    canvasContext.stroke();
    level *= 0.94;
    animationId = requestAnimationFrame(drawMeter);
  }

  button.addEventListener("click", () => running ? stop() : connect());
  volume.addEventListener("input", () => {
    const value = Number(volume.value);
    volumeLabel.textContent = `${Math.round(value * 100)}%`;
    if (gain) gain.gain.setTargetAtTime(value, context.currentTime, 0.01);
  });
  document.addEventListener("visibilitychange", () => {
    if (running && context && context.state === "suspended") {
      context.resume().catch(() => {});
    }
  });
  window.addEventListener("beforeunload", () => stop(false));
  drawMeter();
})();
