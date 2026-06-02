# Mini Claw

Minimal ESP-Claw style app for this Lua runtime.

It keeps only the essential control chain:

```text
WebUI or WeChat text -> LLM API -> tool calls -> simple local actions -> reply
```

## WebUI

Open the app WebUI from the launcher or visit the route exposed by the system.
The Lua service also prints the route on startup.

## Config

Copy values from `config.example.json` into `config.json` in this app directory,
or edit them in the WebUI settings panel.

Required LLM fields:

- `llm_base_url`, for example `https://api.openai.com/v1`
- `llm_api_key`
- `llm_model`

The app calls the Responses API. If `llm_base_url` is a normal `/v1` base URL,
the runtime posts to `/v1/responses`.

Optional WeChat fields:

- `wechat_enabled`
- `wechat_token`
- `wechat_base_url`

This app implements text polling, text replies, and QR login for WeChat ClawBot.
Images, files, and complex device control are intentionally not included.
