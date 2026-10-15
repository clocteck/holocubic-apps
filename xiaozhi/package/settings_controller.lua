-- Runs only in the runtime that owns audio; IPC-only frontends do not write state.
local M = {}
function M.attach(runtime, cfg)
  local Store = dofile(cfg.APP_DIR .. "/store.lua")
  local Preferences = dofile(cfg.APP_DIR .. "/preferences.lua")
  local volume = dofile(cfg.APP_DIR .. "/volume.lua").new()
  cfg.AUDIO.volume = volume.value
  local original_start, original_stop = runtime.start, runtime.stop
  runtime.start = function(self, ...)
    volume.start(function(value)
      cfg.AUDIO.volume=value
      if self.audio then self.audio:set_volume(value) end
      return true
    end)
    return original_start(self, ...)
  end
  runtime.stop = function(...)
    volume.stop()
    return original_stop(...)
  end
  function runtime:set_volume(value)
    local ok,err=volume.set(value)
    if not ok then return false,err end
    return true,{volume=volume.value}
  end
  local original_snapshot = runtime.snapshot
  function runtime:snapshot()
    local s = original_snapshot(self)
    local doc = Store.ensure()
    s.language, s.wake_id = doc.language or "auto", cfg.WAKE_ID
    s.audio_mode = "half_duplex"
    s.audio_error = self.audio and self.audio.last_error or ""
    s.volume_source = volume.supported and "firmware" or "/sd/apps/settings.json"
    s.volume_error, s.volume_pending = volume.error, volume.pending
    s.listening_mode = self.listening_mode
    s.interruption_status = "button_only"
    s.protocol_diagnostics = self.protocol and self.protocol:info() or {}
    s.audio_diagnostics = self.audio and {
      last_failure=self.audio.last_failure, native=self.audio.last_native_status,
      received_packets=self.audio.play_count, sent_packets=self.audio.send_frames,
      events=self.audio.session_events,
      buffered_packets=self.audio.playback_queue and self.audio.playback_queue:count() or 0,
    } or {}
    s.identities = Store.public_identities()
    s.device_mac = Store.device_id() or ""
    s.config_path = Store.PATH
    s.service_mode = cfg.SERVICE_MODE == true
    s.resolved_language = dofile(cfg.APP_DIR .. "/i18n.lua").locale(cfg)
    s.url, s.version = s.websocket_url, s.websocket_version
    s.app_installed = s.app_ui_installed
    s.activation_message = s.message
    s.ui_options = s.ui_options or {}
    s.ui_options.app_styles = s.ui_options.app
    s.ui_options.service_styles = s.ui_options.float
    return s
  end
  local restarting = false
  function runtime:control_session(action)
    if self.state and self.state.state == "fatal_error" then return false, "restart_required" end
    if action ~= "wake" and action ~= "stop" then return false, "unknown_action" end
    if self.ui_control then return self:ui_control(action == "stop" and "dismiss" or "wake") end
    if action == "stop" then self.stop_listening(); return true end
    if self.audio.on_wake then self.audio.on_wake(cfg.WAKE_WORD); return true end
    return false, "not_ready"
  end
  local function restart()
    if restarting then return true end
    if not tmr or not tmr.create then return false, "timer_unavailable" end
    restarting = true
    local timer = tmr.create()
    timer:alarm(250, tmr.ALARM_SINGLE, function(t)
      pcall(function() t:unregister() end)
      runtime.stop("shared configuration changed")
      local ok, err = pcall(dofile, cfg.APP_DIR .. "/main.lua")
      if not ok then print("[xiaozhi] restart failed", err) end
    end)
    return true
  end
  function runtime:set_preferences(doc)
    if restarting then return false, "restart_in_progress" end
    local languages = { auto=true, ["zh-CN"]=true, en=true }
    if not languages[doc.language] or not Preferences.models[doc.wake_id] then
      return false, "invalid_preferences"
    end
    local model = Preferences.models[doc.wake_id]
    for _, name in ipairs({ "_MODEL_INFO_", "wn9_index", "wn9_data" }) do
      if not file.exists(cfg.APP_DIR .. "/wake/" .. model.model .. "/" .. name) then return false, "wake_model_missing" end
    end
    if self.state and (self.state.state == "speaking" or self.state.state == "listening" or self.state.state == "connecting") then
      return false, "stop_session_before_changing_preferences"
    end
    local ok, err = Store.update(function(saved)
      saved.language, saved.wake = doc.language, { id = doc.wake_id }
      saved.wake_word = model.text
      saved.audio = saved.audio or {}
    end)
    if not ok then return false, err end
    local started, why = restart()
    if not started then return false, why end
    return true, { restarting = true }
  end
  function runtime:manage_identity(action, value)
    if restarting then return false, "restart_in_progress" end
    local ok, err = Store.identity_action(action, value)
    if not ok then return false, err end
    if action ~= "rename" and action ~= "delete" then
      -- Cancel in-flight activation before it can save credentials for the old ID.
      if self.activation then self.activation:stop() end
      if self.protocol then self.protocol:stop() end
      local started, why = restart()
      if not started then return false, why end
    end
    return true, { mac = Store.device_id(), restarting = restarting }
  end
  function runtime:set_device_mac(value) return self:manage_identity("set", value) end
  function runtime:repair_pairing(new_identity)
    if new_identity then return self:manage_identity("create") end
    if restarting then return false, "restart_in_progress" end
    if self.activation then self.activation:stop() end
    local ok, err = Store.update(function(doc)
      doc.websocket = { url = "", token = "", version = 1 }
      doc.ota = doc.ota or { url = "https://api.tenclass.net/xiaozhi/ota/" }
      doc.ota.enabled, doc.ota.force = true, false
    end)
    if not ok then return false, err end
    return restart()
  end
end
return M
