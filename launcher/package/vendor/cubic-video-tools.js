(function(global){
  "use strict";

  var DEFAULT_WIDTH = 320;
  var DEFAULT_HEIGHT = 240;
  var DEFAULT_FPS = 20;
  var DEFAULT_QUALITY = 0.72;
  var DEFAULT_AUDIO_RATE = 16000;
  var MAX_AVI_BYTES = 0x7fffffff;
  var IOS_MAX_DURATION_SECONDS = 300;
  var MAX_JPEG_OUTPUT_BYTES = 256 * 1024 * 1024;

  function isAppleMobile(){
    var nav = global.navigator || {};
    var userAgent = String(nav.userAgent || "");
    return /iPad|iPhone|iPod/i.test(userAgent) ||
      (String(nav.platform || "") === "MacIntel" && Number(nav.maxTouchPoints || 0) > 1);
  }

  function maxDurationSeconds(options){
    var requested = Number(options && options.maxDurationSeconds || 600);
    if(!isFinite(requested) || requested <= 0) requested = 600;
    requested = Math.max(1, requested);
    return isAppleMobile() ? Math.min(requested, IOS_MAX_DURATION_SECONDS) : requested;
  }

  function appendJpegFrame(output, frame, budget){
    var nextBytes = budget.bytes + Number(frame && frame.size || 0);
    if(nextBytes > MAX_JPEG_OUTPUT_BYTES){
      throw new Error("Converted JPEG frames exceed the 256 MiB memory limit");
    }
    budget.bytes = nextBytes;
    output.push(frame);
  }

  function cancelledError(){
    var error = new Error("Conversion cancelled");
    error.name = "AbortError";
    return error;
  }

  function checkCancelled(options){
    if(options && options.signal && options.signal.aborted) throw cancelledError();
  }

  function emit(options, progress){
    checkCancelled(options);
    if(options && typeof options.onProgress === "function"){
      options.onProgress(progress || {});
    }
    checkCancelled(options);
  }

  function nextPaint(){
    return new Promise(function(resolve){
      if(typeof requestAnimationFrame === "function"){
        requestAnimationFrame(function(){ requestAnimationFrame(resolve); });
      }else{
        setTimeout(resolve, 0);
      }
    });
  }

  function shortDelay(ms, options){
    return new Promise(function(resolve, reject){
      var signal = options && options.signal;
      var timer = setTimeout(function(){ cleanup(); resolve(); }, ms);
      function cleanup(){
        clearTimeout(timer);
        if(signal) signal.removeEventListener("abort", aborted);
      }
      function aborted(){ cleanup(); reject(cancelledError()); }
      if(signal){
        if(signal.aborted){ aborted(); return; }
        signal.addEventListener("abort", aborted, { once: true });
      }
    });
  }

  function readFileArrayBuffer(file, options){
    return new Promise(function(resolve, reject){
      var reader = new FileReader();
      var signal = options && options.signal;
      function cleanup(){ if(signal) signal.removeEventListener("abort", aborted); }
      function aborted(){
        cleanup();
        try{ reader.abort(); }catch(ignore){}
        reject(cancelledError());
      }
      reader.onload = function(){ cleanup(); resolve(reader.result); };
      reader.onerror = function(){ cleanup(); reject(reader.error || new Error("File read failed")); };
      reader.onabort = function(){ cleanup(); reject(cancelledError()); };
      if(signal){
        if(signal.aborted){ aborted(); return; }
        signal.addEventListener("abort", aborted, { once: true });
      }
      reader.readAsArrayBuffer(file);
    });
  }

  function canvasToJpeg(canvas, quality){
    return new Promise(function(resolve, reject){
      canvas.toBlob(function(blob){
        if(blob){ resolve(blob); }
        else{ reject(new Error("JPEG frame encoding failed")); }
      }, "image/jpeg", quality);
    });
  }

  function loadImageBlob(blob){
    if(typeof createImageBitmap === "function"){
      return createImageBitmap(blob);
    }
    return new Promise(function(resolve, reject){
      var url = URL.createObjectURL(blob);
      var image = new Image();
      image.onload = function(){ URL.revokeObjectURL(url); resolve(image); };
      image.onerror = function(){ URL.revokeObjectURL(url); reject(new Error("MJPEG frame decode failed")); };
      image.src = url;
    });
  }

  function drawFitted(ctx, source, sourceWidth, sourceHeight, width, height){
    var scale = Math.min(width / sourceWidth, height / sourceHeight);
    var targetWidth = Math.max(1, Math.round(sourceWidth * scale));
    var targetHeight = Math.max(1, Math.round(sourceHeight * scale));
    var left = Math.floor((width - targetWidth) / 2);
    var top = Math.floor((height - targetHeight) / 2);
    ctx.fillStyle = "#000";
    ctx.fillRect(0, 0, width, height);
    ctx.imageSmoothingEnabled = true;
    if("imageSmoothingQuality" in ctx) ctx.imageSmoothingQuality = "high";
    ctx.drawImage(source, left, top, targetWidth, targetHeight);
  }

  function u16(view, offset, value){ view.setUint16(offset, value >>> 0, true); }
  function u32(view, offset, value){ view.setUint32(offset, value >>> 0, true); }
  function fourcc(bytes, offset, text){
    for(var i = 0; i < 4; i += 1) bytes[offset + i] = text.charCodeAt(i) || 32;
  }

  function makeChunk(id, payload){
    var size = payload.byteLength != null ? payload.byteLength : payload.size;
    var header = new Uint8Array(8);
    fourcc(header, 0, id);
    u32(new DataView(header.buffer), 4, size);
    return new Blob(size & 1 ? [header, payload, new Uint8Array(1)] : [header, payload]);
  }

  function makeList(type, parts){
    var payloadSize = 4;
    parts.forEach(function(part){ payloadSize += part.size; });
    var header = new Uint8Array(12);
    fourcc(header, 0, "LIST");
    u32(new DataView(header.buffer), 4, payloadSize);
    fourcc(header, 8, type);
    return new Blob([header].concat(parts));
  }

  function buildAvi(frames, width, height, fps){
    if(!frames.length) throw new Error("No video frames were produced");
    var totalFrameBytes = 0;
    var maxFrameBytes = 0;
    frames.forEach(function(frame){
      totalFrameBytes += 8 + frame.size + (frame.size & 1);
      maxFrameBytes = Math.max(maxFrameBytes, frame.size);
    });

    var avih = new Uint8Array(56);
    var avihView = new DataView(avih.buffer);
    u32(avihView, 0, Math.round(1000000 / fps));
    u32(avihView, 4, Math.min(0xffffffff, Math.ceil((totalFrameBytes / frames.length) * fps)));
    u32(avihView, 12, 0x10);
    u32(avihView, 16, frames.length);
    u32(avihView, 24, 1);
    u32(avihView, 28, maxFrameBytes);
    u32(avihView, 32, width);
    u32(avihView, 36, height);

    var strh = new Uint8Array(56);
    var strhView = new DataView(strh.buffer);
    fourcc(strh, 0, "vids");
    fourcc(strh, 4, "MJPG");
    u32(strhView, 20, 1);
    u32(strhView, 24, fps);
    u32(strhView, 32, frames.length);
    u32(strhView, 36, maxFrameBytes);
    u32(strhView, 40, 0xffffffff);
    u16(strhView, 48, 0);
    u16(strhView, 50, 0);
    u16(strhView, 52, width);
    u16(strhView, 54, height);

    var strf = new Uint8Array(40);
    var strfView = new DataView(strf.buffer);
    u32(strfView, 0, 40);
    strfView.setInt32(4, width, true);
    strfView.setInt32(8, height, true);
    u16(strfView, 12, 1);
    u16(strfView, 14, 24);
    fourcc(strf, 16, "MJPG");
    u32(strfView, 20, width * height * 3);

    var strl = makeList("strl", [makeChunk("strh", strh), makeChunk("strf", strf)]);
    var hdrl = makeList("hdrl", [makeChunk("avih", avih), strl]);

    var moviHeader = new Uint8Array(12);
    fourcc(moviHeader, 0, "LIST");
    u32(new DataView(moviHeader.buffer), 4, 4 + totalFrameBytes);
    fourcc(moviHeader, 8, "movi");

    var idx = new Uint8Array(frames.length * 16);
    var idxView = new DataView(idx.buffer);
    var moviOffset = 4;
    var frameParts = [];
    frames.forEach(function(frame, index){
      var base = index * 16;
      fourcc(idx, base, "00dc");
      u32(idxView, base + 4, 0x10);
      u32(idxView, base + 8, moviOffset);
      u32(idxView, base + 12, frame.size);
      var chunk = makeChunk("00dc", frame);
      frameParts.push(chunk);
      moviOffset += chunk.size;
    });
    var idxChunk = makeChunk("idx1", idx);
    var riffPayloadSize = 4 + hdrl.size + moviHeader.byteLength + totalFrameBytes + idxChunk.size;
    var fileSize = 8 + riffPayloadSize;
    if(fileSize > MAX_AVI_BYTES) throw new Error("Converted AVI is too large");

    var riff = new Uint8Array(12);
    fourcc(riff, 0, "RIFF");
    u32(new DataView(riff.buffer), 4, riffPayloadSize);
    fourcc(riff, 8, "AVI ");
    return new Blob([riff, hdrl, moviHeader].concat(frameParts, [idxChunk]), { type: "video/x-msvideo" });
  }

  function readAviRate(bytes){
    var view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    for(var i = 0; i + 64 <= bytes.length; i += 1){
      if(bytes[i] === 0x73 && bytes[i + 1] === 0x74 && bytes[i + 2] === 0x72 && bytes[i + 3] === 0x68){
        var size = view.getUint32(i + 4, true);
        if(size >= 40 && i + 8 + size <= bytes.length &&
           bytes[i + 8] === 0x76 && bytes[i + 9] === 0x69 && bytes[i + 10] === 0x64 && bytes[i + 11] === 0x73){
          var scale = view.getUint32(i + 28, true);
          var rate = view.getUint32(i + 32, true);
          if(scale && rate) return rate / scale;
        }
      }
    }
    return DEFAULT_FPS;
  }

  function findJpegRanges(bytes){
    var ranges = [];
    var start = -1;
    for(var i = 0; i + 1 < bytes.length; i += 1){
      if(start < 0 && bytes[i] === 0xff && bytes[i + 1] === 0xd8){
        start = i;
        i += 1;
      }else if(start >= 0 && bytes[i] === 0xff && bytes[i + 1] === 0xd9){
        ranges.push([start, i + 2]);
        start = -1;
        i += 1;
      }
    }
    return ranges;
  }

  function makeCanvas(width, height){
    var canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    var ctx = canvas.getContext("2d", { alpha: false });
    if(!ctx) throw new Error("Canvas is not available in this browser");
    return { canvas: canvas, ctx: ctx };
  }

  async function convertMjpeg(file, options, width, height, fps, quality){
    emit(options, { phase: "analyze", current: 0, total: 0 });
    var source = new Uint8Array(await readFileArrayBuffer(file, options));
    checkCancelled(options);
    var ranges = findJpegRanges(source);
    if(!ranges.length) throw new Error("No MJPEG frames were found");
    var sourceFps = /\.avi$/i.test(file.name || "") ? readAviRate(source) : fps;
    if(!isFinite(sourceFps) || sourceFps <= 0) sourceFps = fps;
    var duration = ranges.length / sourceFps;
    var maxDuration = maxDurationSeconds(options);
    if(duration > maxDuration) throw new Error("Video is longer than " + Math.round(maxDuration / 60) + " minutes");
    var targetCount = Math.max(1, Math.round(duration * fps));
    var audio = await extractAudio(file, outputName(file.name), duration, options);
    checkCancelled(options);
    var drawing = makeCanvas(width, height);
    var output = [];
    var budget = { bytes: 0 };
    var lastSourceIndex = -1;
    var lastFrame = null;
    for(var i = 0; i < targetCount; i += 1){
      checkCancelled(options);
      var sourceIndex = Math.min(ranges.length - 1, Math.floor(i * sourceFps / fps));
      if(sourceIndex !== lastSourceIndex){
        var range = ranges[sourceIndex];
        var jpeg = new Blob([source.subarray(range[0], range[1])], { type: "image/jpeg" });
        var image = await loadImageBlob(jpeg);
        var imageWidth = image.width || image.naturalWidth;
        var imageHeight = image.height || image.naturalHeight;
        drawFitted(drawing.ctx, image, imageWidth, imageHeight, width, height);
        if(typeof image.close === "function") image.close();
        lastFrame = await canvasToJpeg(drawing.canvas, quality);
        lastSourceIndex = sourceIndex;
      }
      appendJpegFrame(output, lastFrame, budget);
      emit(options, { phase: "convert", current: i + 1, total: targetCount, duration: duration, mediaTime: i / fps, outputBytes: budget.bytes });
      if((i & 7) === 7) await nextPaint();
    }
    return { frames: output, audio: audio, duration: duration, jpegBytes: budget.bytes };
  }

  function waitForVideoEvent(video, eventName, errorText, timeoutMs, options){
    return new Promise(function(resolve, reject){
      var timer = setTimeout(function(){ cleanup(); reject(new Error(errorText)); }, timeoutMs || 15000);
      var signal = options && options.signal;
      function cleanup(){
        clearTimeout(timer);
        video.removeEventListener(eventName, done);
        video.removeEventListener("error", failed);
        if(signal) signal.removeEventListener("abort", aborted);
      }
      function done(){ cleanup(); resolve(); }
      function failed(){ cleanup(); reject(new Error(errorText)); }
      function aborted(){ cleanup(); reject(cancelledError()); }
      video.addEventListener(eventName, done, { once: true });
      video.addEventListener("error", failed, { once: true });
      if(signal){
        if(signal.aborted){ aborted(); return; }
        signal.addEventListener("abort", aborted, { once: true });
      }
    });
  }

  function beginPresentedFrameWait(video, errorText, timeoutMs, options){
    if(typeof video.requestVideoFrameCallback !== "function") return null;
    return new Promise(function(resolve, reject){
      var frameId = null;
      var signal = options && options.signal;
      var timer = setTimeout(function(){
        cleanup();
        reject(new Error(errorText || "Video frame decode timed out"));
      }, timeoutMs || 20000);
      function cleanup(){
        clearTimeout(timer);
        if(frameId !== null && typeof video.cancelVideoFrameCallback === "function"){
          try{ video.cancelVideoFrameCallback(frameId); }catch(ignore){}
        }
        frameId = null;
        if(signal) signal.removeEventListener("abort", aborted);
      }
      function done(now, metadata){
        frameId = null;
        cleanup();
        resolve(metadata || {});
      }
      function aborted(){ cleanup(); reject(cancelledError()); }
      if(signal){
        if(signal.aborted){ aborted(); return; }
        signal.addEventListener("abort", aborted, { once: true });
      }
      try{
        frameId = video.requestVideoFrameCallback(done);
      }catch(error){
        cleanup();
        reject(error);
      }
    });
  }

  async function waitForFallbackFrame(options){
    checkCancelled(options);
    await shortDelay(32, options);
    await nextPaint();
    checkCancelled(options);
  }

  async function waitForVideoData(video, options){
    if(video.readyState >= 2) return;
    await waitForVideoEvent(video, "loadeddata", "Browser did not decode the first video frame", 20000, options);
  }

  async function seekVideo(video, time, options){
    checkCancelled(options);
    if(Math.abs(video.currentTime - time) < 0.0005){
      await waitForVideoData(video, options);
      return;
    }
    var frameWaiting = beginPresentedFrameWait(video, "Video frame decode timed out after seek", 20000, options);
    var seekWaiting = waitForVideoEvent(video, "seeked", "Video frame seek failed", 20000, options);
    video.currentTime = time;
    if(frameWaiting){
      await Promise.all([seekWaiting, frameWaiting]);
    }else{
      await seekWaiting;
      await waitForFallbackFrame(options);
    }
    checkCancelled(options);
  }

  async function convertBrowserVideo(file, options, width, height, fps, quality){
    emit(options, { phase: "analyze", current: 0, total: 0 });
    var url = URL.createObjectURL(file);
    var video = document.createElement("video");
    video.muted = true;
    video.defaultMuted = true;
    video.playsInline = true;
    video.setAttribute("muted", "");
    video.setAttribute("playsinline", "");
    video.setAttribute("webkit-playsinline", "");
    video.preload = "auto";
    video.setAttribute("aria-hidden", "true");
    video.tabIndex = -1;
    video.style.cssText = "position:fixed;width:1px;height:1px;left:0;top:0;opacity:.01;pointer-events:none;z-index:2147483647";
    (document.body || document.documentElement).appendChild(video);
    var firstFrameWaiting = beginPresentedFrameWait(video, "Browser did not present the first video frame", 20000, options);
    if(firstFrameWaiting) firstFrameWaiting.catch(function(){});
    try{
      video.src = url;
      video.load();
      await waitForVideoEvent(video, "loadedmetadata", "Browser cannot decode this MP4 video", 20000, options);
      await waitForVideoData(video, options);
      if(firstFrameWaiting){
        await firstFrameWaiting;
      }else{
        await waitForFallbackFrame(options);
      }
      var duration = Number(video.duration);
      if(!isFinite(duration) || duration <= 0) throw new Error("Video duration is invalid");
      var maxDuration = maxDurationSeconds(options);
      if(duration > maxDuration) throw new Error("Video is longer than " + Math.round(maxDuration / 60) + " minutes");
      var total = Math.max(1, Math.floor(duration * fps));
      var audio = await extractAudio(file, outputName(file.name), duration, options);
      checkCancelled(options);
      var drawing = makeCanvas(width, height);
      var output = [];
      var budget = { bytes: 0 };
      for(var i = 0; i < total; i += 1){
        checkCancelled(options);
        var time = Math.min(Math.max(0, duration - 0.001), i / fps);
        await seekVideo(video, time, options);
        drawFitted(drawing.ctx, video, video.videoWidth, video.videoHeight, width, height);
        var frame = await canvasToJpeg(drawing.canvas, quality);
        appendJpegFrame(output, frame, budget);
        emit(options, { phase: "convert", current: i + 1, total: total, duration: duration, mediaTime: time, outputBytes: budget.bytes });
        if((i & 3) === 3) await nextPaint();
      }
      return { frames: output, audio: audio, duration: duration, jpegBytes: budget.bytes };
    }finally{
      video.pause();
      video.removeAttribute("src");
      video.load();
      if(video.parentNode) video.parentNode.removeChild(video);
      URL.revokeObjectURL(url);
    }
  }

  function outputName(name){
    var source = String(name || "video").replace(/[\\/:*?"<>|]+/g, "_");
    source = source.replace(/\.[^.]+$/, "");
    return (source || "video") + "_320x240_20fps.avi";
  }

  function audioOutputName(videoName){
    return String(videoName || "video.avi").replace(/\.avi$/i, ".wav");
  }

  function writeAscii(bytes, offset, text){
    for(var i = 0; i < text.length; i += 1) bytes[offset + i] = text.charCodeAt(i) & 0xff;
  }

  function makeMonoWav(audioBuffer, sampleRate, duration, options){
    var sourceRate = Math.max(1, Number(audioBuffer.sampleRate || 44100));
    var channelCount = Math.max(1, Number(audioBuffer.numberOfChannels || 1));
    var seconds = Math.max(0, Math.min(Number(audioBuffer.duration || 0), Number(duration || audioBuffer.duration || 0)));
    var sampleCount = Math.max(1, Math.floor(seconds * sampleRate));
    var header = new Uint8Array(44);
    var headerView = new DataView(header.buffer);
    writeAscii(header, 0, "RIFF");
    u32(headerView, 4, 36 + sampleCount * 2);
    writeAscii(header, 8, "WAVE");
    writeAscii(header, 12, "fmt ");
    u32(headerView, 16, 16);
    u16(headerView, 20, 1);
    u16(headerView, 22, 1);
    u32(headerView, 24, sampleRate);
    u32(headerView, 28, sampleRate * 2);
    u16(headerView, 32, 2);
    u16(headerView, 34, 16);
    writeAscii(header, 36, "data");
    u32(headerView, 40, sampleCount * 2);

    var channels = [];
    for(var c = 0; c < channelCount; c += 1) channels.push(audioBuffer.getChannelData(c));
    var chunk = 32768;
    return (async function(){
      var parts = [header];
      for(var start = 0; start < sampleCount; start += chunk){
        checkCancelled(options);
        var end = Math.min(sampleCount, start + chunk);
        var pcm = new Uint8Array((end - start) * 2);
        var pcmView = new DataView(pcm.buffer);
        for(var i = start; i < end; i += 1){
          var sourcePosition = i * sourceRate / sampleRate;
          var left = Math.min(channels[0].length - 1, Math.floor(sourcePosition));
          var right = Math.min(channels[0].length - 1, left + 1);
          var mix = 0;
          var fraction = sourcePosition - left;
          for(var channel = 0; channel < channels.length; channel += 1){
            var data = channels[channel];
            mix += data[left] + (data[right] - data[left]) * fraction;
          }
          mix = Math.max(-1, Math.min(1, mix / channels.length));
          pcmView.setInt16((i - start) * 2, mix < 0 ? Math.round(mix * 32768) : Math.round(mix * 32767), true);
        }
        parts.push(pcm);
        emit(options, { phase: "audio", current: end, total: sampleCount, duration: seconds });
        await nextPaint();
      }
      return new Blob(parts, { type: "audio/wav" });
    })();
  }

  async function extractAudio(file, videoName, duration, options){
    var AudioContextClass = global.AudioContext || global.webkitAudioContext;
    if(!AudioContextClass) return { file: null, error: "Web Audio API is unavailable" };
    var sampleRate = Math.max(8000, Math.min(24000, Number(options.audioSampleRate || DEFAULT_AUDIO_RATE) | 0));
    var context;
    try{
      context = new AudioContextClass({ sampleRate: sampleRate });
    }catch(ignore){
      context = new AudioContextClass();
    }
    var signal = options && options.signal;
    var abortContext = function(){
      if(context && typeof context.close === "function") context.close().catch(function(){});
    };
    if(signal) signal.addEventListener("abort", abortContext, { once: true });
    try{
      emit(options, { phase: "audio-decode", current: 0, total: 0 });
      var input = await readFileArrayBuffer(file, options);
      checkCancelled(options);
      var decoded = await context.decodeAudioData(input);
      checkCancelled(options);
      if(!decoded || !decoded.length || !decoded.duration) return { file: null, error: "No audio track was found" };
      var wav = await makeMonoWav(decoded, sampleRate, duration, options);
      var audioFile = new File([wav], audioOutputName(videoName), { type: "audio/wav", lastModified: Date.now() });
      return { file: audioFile, sampleRate: sampleRate, duration: Math.min(decoded.duration, duration) };
    }catch(error){
      if(error && error.name === "AbortError") throw error;
      return { file: null, error: error && error.message ? error.message : "Audio track decode failed" };
    }finally{
      if(signal) signal.removeEventListener("abort", abortContext);
      if(context && typeof context.close === "function"){
        try{ await context.close(); }catch(ignore){}
      }
    }
  }

  async function convertVideo(file, inputOptions){
    var options = inputOptions || {};
    var width = Math.max(1, Number(options.width || DEFAULT_WIDTH) | 0);
    var height = Math.max(1, Number(options.height || DEFAULT_HEIGHT) | 0);
    var fps = Math.max(1, Number(options.fps || DEFAULT_FPS) | 0);
    if(isAppleMobile()) fps = Math.min(fps, DEFAULT_FPS);
    var quality = Math.max(0.35, Math.min(0.95, Number(options.jpegQuality || DEFAULT_QUALITY)));
    var lower = String(file && file.name || "").toLowerCase();
    if(!file) throw new Error("No video file selected");
    checkCancelled(options);
    var converted;
    if(/\.(avi|mjpeg|mjpg)$/.test(lower)){
      converted = await convertMjpeg(file, options, width, height, fps, quality);
    }else if(/\.(mp4|m4v|mov)$/.test(lower) || String(file.type || "").indexOf("video/") === 0){
      converted = await convertBrowserVideo(file, options, width, height, fps, quality);
    }else{
      throw new Error("Unsupported video format");
    }
    var frames = converted.frames;
    var audio = converted.audio || { file: null, error: "Audio track decode failed" };
    emit(options, { phase: "mux", current: frames.length, total: frames.length });
    await nextPaint();
    var avi = buildAvi(frames, width, height, fps);
    var videoFileName = outputName(file.name);
    checkCancelled(options);
    emit(options, {
      phase: "done",
      current: frames.length,
      total: frames.length,
      outputBytes: avi.size + (audio.file ? audio.file.size : 0),
      audioBytes: audio.file ? audio.file.size : 0,
      hasAudio: !!audio.file,
      audioError: audio.error || ""
    });
    var videoFile = new File([avi], videoFileName, { type: "video/x-msvideo", lastModified: Date.now() });
    return {
      file: videoFile,
      files: audio.file ? [videoFile, audio.file] : [videoFile],
      audioFile: audio.file,
      audioError: audio.error || "",
      width: width,
      height: height,
      fps: fps,
      frames: frames.length,
      size: avi.size,
      jpegBytes: converted.jpegBytes || 0
    };
  }

  global.CubicVideoTools = {
    convertVideo: convertVideo,
    version: "1.2.0",
    limits: {
      iosMaxDurationSeconds: IOS_MAX_DURATION_SECONDS,
      maxJpegOutputBytes: MAX_JPEG_OUTPUT_BYTES
    }
  };
})(window);
