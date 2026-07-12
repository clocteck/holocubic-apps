local config = {}

config.host = "192.168.0.100"
config.port = 17321
config.path = "/events"

config.timeout_ms = 7000
config.reconnect_ms = 2000
config.stale_ms = 120000
config.watchdog_ms = 1000
config.serial_log = true

return config
