# Runtime modes

See README.md for the current 1.2 ownership model.

- Frontend only: standalone speech runtime.
- Service only: service speech runtime and floating UI.
- Both: Service owns native resources, identity and connection; frontend is IPC UI.
- An installed but not-yet-ready service is awaited, never raced by a second core.
- Shared state: /sd/data/xiaozhi/config.json. Neither package overwrites it on deployment.
