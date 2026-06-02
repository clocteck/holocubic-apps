# Voice AI Bridge

Desktop HTTP bridge for the `voice_ai` Lua app.

The device uploads raw PCM audio. This service converts it to WAV, saves a copy under `tools/temp`, transcribes it, reads `tools/voice_ai_bridge/agent.md`, and sends the transcript to `gpt-5.4-mini`. For explicit visual requests, it also appends `tools/voice_ai_bridge/lvgl_prompt.md` so normal chat does not carry the long LVGL API whitelist.

## Run

```powershell
$env:OPENAI_API_KEY="sk-..."
python .\tools\voice_ai_bridge\server.py --host 0.0.0.0 --port 8790
```

The Lua app defaults to:

```text
http://192.168.0.80:8790
```

If the computer IP changes, edit `/sd/apps/voice_ai/config.json`.

## Endpoint

```text
GET  /api/health
POST /api/chat
```

`POST /api/chat` expects raw PCM in the request body and these headers. It returns as soon as transcription is ready; AI generation continues in the background.

```text
Content-Type: application/octet-stream
X-Sample-Rate: 16000
X-Bits: 32
X-Channels: 1
X-Reply-Limit: 100
```

Response:

```json
{
  "ok": true,
  "transcript": "用户说的话",
  "pending": true,
  "id": "result id",
  "reply": "",
  "ui_code": ""
}
```

Poll the AI result with:

```text
GET /api/result?id=<result id>
```

Pending result:

```json
{
  "ok": true,
  "id": "result id",
  "pending": true,
  "transcript": "用户说的话",
  "reply": "",
  "ui_code": ""
}
```

Completed result:

```json
{
  "ok": true,
  "id": "result id",
  "pending": false,
  "transcript": "用户说的话",
  "reply": "100字以内的中文回复",
  "ui_code": "return function(ctx) ... end"
}
```

`ui_code` is expected to create a new independent LVGL screen and return `{ screen = screen, cleanup = function() end }`. The device app runs it in a restricted Lua environment with most device `lv_*` bindings available, except screen switching, root cleanup, object deletion, resource load/free, AVI playback, and other APIs that can break the host app.

For normal text replies, `ui_code` should be an empty string. The bridge reads `agent.md` and, when needed, `lvgl_prompt.md` for every chat request, so prompt changes do not require restarting the service.
The bridge keeps a small in-memory conversation context, capped around 1.8k characters, for follow-up questions. It is cleared when the bridge process restarts.

## Model settings

Defaults:

```text
VOICE_AI_MODEL=gpt-5.4-mini
VOICE_AI_STT=faster-whisper
VOICE_AI_LOCAL_STT_MODEL=medium
VOICE_AI_TRANSCRIBE_MODEL=gpt-4o-mini-transcribe
VOICE_AI_WEB_SEARCH=1
```

`tiny` / `tiny.en` are automatically upgraded to `medium` because they are too inaccurate for this app. For higher accuracy, start with `--local-stt-model large-v3`; it is slower and uses more memory.

Each request writes:

```text
tools/temp/voice_ai-YYYYMMDD-HHMMSS-xxxxxxxx.wav
tools/temp/voice_ai-YYYYMMDD-HHMMSS-xxxxxxxx.json
```

Local faster-whisper models default to the project cache:

```text
tools/hf_cache
```

The prompt in `tools/voice_ai_bridge/agent.md` requires Simplified Chinese, direct wording, no Markdown, and 100 characters or less. `tools/voice_ai_bridge/lvgl_prompt.md` is appended only for visual UI requests. The server also truncates replies and applies a lightweight Traditional-to-Simplified cleanup as final guards.

Web search is enabled by default for weather, news, prices, and other current information. Disable it with:

```powershell
$env:VOICE_AI_WEB_SEARCH="0"
# or
python .\tools\voice_ai_bridge\server.py --no-web-search
```
