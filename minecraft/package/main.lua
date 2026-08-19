local APP = {
  DIR = "/sd/apps/classicube",
  MODULE = "/sd/apps/classicube/modules/classicube.so",
  SOURCE = "ble-main",
  POLL_MS = 32,
  SERVICE_POLL_MS = 50,
  SERVICE_TIMEOUT_MS = 10000,
  TRIGGER_PRESS = 32768,
  TRIGGER_RELEASE = 16384,
  ACTIVITY_DEADZONE = 4000,
}

if app and app.current then
  local current = app.current()
  local entry = current and current.entry
  local dir = type(entry) == "string" and entry:gsub("\\", "/"):match("^(.*)/[^/]+$") or nil
  if dir and dir ~= "" then
    APP.DIR = dir
    APP.MODULE = dir .. "/modules/classicube.so"
  end
end

local function log(...)
  print("[classicube]", ...)
end

local function bit_set(mask, bit)
  mask = tonumber(mask) or 0
  return bit > 0 and math.floor(mask / bit) % 2 >= 1
end

local function raw_buttons(state)
  if type(state) ~= "table" then return 0 end
  return tonumber(state.buttons or state.buttons_mask or state.mask or state.button_mask) or 0
end

local function connected(state)
  if type(state) ~= "table" then return false end
  if state.connected == nil then return true end
  return state.connected == true or state.connected == 1 or state.connected == "true"
end

local cube
local current = { mask = -1, lx = 0, ly = 0, rx = 0, ry = 0 }
local triggers = { lt = false, rt = false }
local controller_trace = { connected = nil, activity = false }
local exiting = false
local game_started = false
local startup_timer
local poll_timer
local exit_timer
local suspended_service_ids = {}
local suspended_service_set = {}
local stop_requested = {}
local services_restored = false

local function stop_timer(timer)
  if not timer then return end
  pcall(function() timer:stop() end)
  pcall(function() timer:unregister() end)
end

local function list_running_services()
  if not app or not app.services then return nil, "app.services unavailable" end
  local ok, services = pcall(function() return app.services() end)
  if not ok then return nil, tostring(services) end
  if type(services) ~= "table" then
    return nil, "app.services returned " .. type(services)
  end
  return services
end

local function restore_services()
  if services_restored then return end
  services_restored = true
  if #suspended_service_ids == 0 then return end
  if not app or not app.start_service then
    log("service restore unavailable")
    return
  end

  local running = {}
  local services, list_error = list_running_services()
  if services then
    for _, service in ipairs(services) do
      if type(service) == "table" and type(service.id) == "string" then
        running[service.id] = true
      end
    end
  else
    log("service restore snapshot failed", tostring(list_error))
  end

  for _, id in ipairs(suspended_service_ids) do
    if not running[id] then
      local call_ok, restored, restore_error = pcall(function()
        return app.start_service(id)
      end)
      if call_ok and restored then
        log("service restore requested", id)
      else
        log("service restore failed", id, tostring(call_ok and restore_error or restored))
      end
    end
  end
end

local function finish_exit()
  stop_timer(startup_timer); stop_timer(poll_timer); stop_timer(exit_timer)
  if controller and controller.on then pcall(function() controller.on(APP.SOURCE, nil) end) end
  if app and app.on then pcall(function() app.on("key", nil) end) end
  restore_services()
  if app and app.exit then pcall(function() app.exit() end) end
end

local function request_exit(reason)
  if exiting then return end
  exiting = true
  log("exit", reason or "")
  if cube then
    pcall(function() cube.set_input(0, 0, 0, 0, 0) end)
    pcall(function() cube.stop() end)
  end
  if tmr and tmr.create then
    exit_timer = tmr.create()
    if pcall(function() exit_timer:alarm(350, tmr.ALARM_SINGLE or 0, finish_exit) end) then return end
  end
  finish_exit()
end

local function configure_home_exit()
  local home_managed = false
  if app and app.on then
    local key_api = rawget(_G, "key")
    local home_code = (key_api and key_api.HOME) or rawget(_G, "KEY_HOME") or 5
    local short_type = (key_api and key_api.SHORT) or rawget(_G, "KEY_EVENT_SHORT") or 2
    home_managed = pcall(function()
      app.on("key", function(_, event_type, key_code)
        if event_type == short_type and key_code == home_code then
          request_exit("device HOME")
        end
      end)
    end)
  end
  if app and app.set_home_exit then
    pcall(function() app.set_home_exit(not home_managed) end)
  end
end

configure_home_exit()

local function map_state(state)
  if not connected(state) then
    triggers.lt, triggers.rt = false, false
    return 0, 0, 0, 0, 0, false
  end
  local raw = raw_buttons(state)
  local mask = 0
  local function set_module(module_bit)
    if module_bit and module_bit > 0 and not bit_set(mask, module_bit) then
      mask = mask + module_bit
    end
  end
  local function add(raw_bit, module_bit, named)
    if bit_set(raw, raw_bit) or named then set_module(module_bit) end
  end
  local function trigger_active(was_active, value)
    if value == true or value == "true" then return true end
    if value == false or value == "false" or value == nil then return false end
    value = tonumber(value) or 0
    if value == 1 then value = 65535 end
    if was_active then return value >= APP.TRIGGER_RELEASE end
    return value >= APP.TRIGGER_PRESS
  end
  add(1, cube.BTN_UP, state.up == true)
  add(2, cube.BTN_DOWN, state.down == true)
  add(4, cube.BTN_LEFT, state.left == true)
  add(8, cube.BTN_RIGHT, state.right == true)
  add(16, cube.BTN_A, state.a == true)
  add(32, cube.BTN_SELECT, state.b == true)
  add(64, cube.BTN_X, state.x == true)
  add(128, cube.BTN_Y, state.y == true)
  add(256, cube.BTN_L, state.l == true or state.lb == true)
  add(512, cube.BTN_R, state.r == true or state.rb == true)
  add(1024, cube.BTN_L2, state.ls == true or state.l3 == true or state.lstick == true)
  add(2048, cube.BTN_R2, state.rs == true or state.r3 == true or state.rstick == true)
  add(4096, cube.BTN_SELECT, state.select == true or state.back == true)
  add(8192, cube.BTN_START, state.start == true or state.menu == true)
  triggers.lt = trigger_active(triggers.lt, state.lt or state.l2)
  triggers.rt = trigger_active(triggers.rt, state.rt or state.r2)
  if triggers.lt then set_module(cube.BTN_R) end
  if triggers.rt then set_module(cube.BTN_L) end
  local home = bit_set(raw, 32768) or state.home == true or state.guide == true
  return mask, tonumber(state.lx) or 0, tonumber(state.ly) or 0,
         tonumber(state.rx) or 0, tonumber(state.ry) or 0, home
end

local function update_input(event_state)
  if exiting then return end
  local state = type(event_state) == "table" and event_state or nil
  if not state and controller and controller.state then
    local ok, value = pcall(function() return controller.state(APP.SOURCE) end)
    if ok then state = value end
  end
  local is_connected = connected(state)
  if controller_trace.connected ~= is_connected then
    controller_trace.connected = is_connected
    controller_trace.activity = false
    if is_connected then
      log("controller connected", tostring(state.name or state.device_name or state.profile or APP.SOURCE))
    else
      log("controller disconnected", APP.SOURCE)
    end
  end
  local mask, lx, ly, rx, ry, home = map_state(state)
  if home then request_exit("controller HOME"); return end
  if is_connected and not controller_trace.activity and
     (mask ~= 0 or math.abs(lx) > APP.ACTIVITY_DEADZONE or
      math.abs(ly) > APP.ACTIVITY_DEADZONE or math.abs(rx) > APP.ACTIVITY_DEADZONE or
      math.abs(ry) > APP.ACTIVITY_DEADZONE) then
    controller_trace.activity = true
    log("controller input", string.format("mask=0x%X lx=%d ly=%d rx=%d ry=%d lt=%s rt=%s",
        mask, lx, ly, rx, ry, tostring(state.lt or state.l2 or 0), tostring(state.rt or state.r2 or 0)))
  end
  if mask ~= current.mask or lx ~= current.lx or ly ~= current.ly or
     rx ~= current.rx or ry ~= current.ry then
    local ok, err = pcall(function() cube.set_input(mask, lx, ly, rx, ry) end)
    if not ok then log("input failed", tostring(err)) end
    current.mask, current.lx, current.ly, current.rx, current.ry = mask, lx, ly, rx, ry
  end
end

local function start_game()
  if game_started or exiting then return end
  stop_timer(startup_timer)
  startup_timer = nil

  local ok_module, loaded = pcall(function() return require(APP.MODULE) end)
  if not ok_module or type(loaded) ~= "table" then
    log("module load failed", tostring(loaded))
    request_exit("module load failed")
    return
  end
  cube = loaded

  local call_ok, started, start_error = pcall(function()
    return cube.start({ root = APP.DIR })
  end)
  if not call_ok or not started then
    log("start failed", tostring(call_ok and start_error or started))
    request_exit("start failed")
    return
  end
  game_started = true

  if controller and controller.on then
    local ok_subscribe, subscribe_error = pcall(function()
      controller.on(APP.SOURCE, function(source, state)
        if type(state) ~= "table" and type(source) == "table" then state = source end
        update_input(state)
      end)
    end)
    if ok_subscribe then
      log("controller subscribed", APP.SOURCE)
    else
      log("controller subscribe failed", tostring(subscribe_error))
    end
  else
    log("controller API unavailable")
  end
  update_input()

  if tmr and tmr.create then
    poll_timer = tmr.create()
    poll_timer:alarm(APP.POLL_MS, tmr.ALARM_AUTO or 1, function()
      if app and app.exiting and app.exiting() then request_exit("app exiting"); return end
      update_input()
    end)
  else
    log("tmr API unavailable; controller fallback polling disabled")
  end

  log("started", "3D 192x144 scaled + UI 320x240 SoftFP low-effects")
end

local function request_service_stop(service, restore_after_exit)
  if type(service) ~= "table" or type(service.id) ~= "string" then
    return nil, "invalid service record"
  end
  local instance_id = tonumber(service.instance_id)
  local target = instance_id and instance_id > 0 and instance_id or service.id
  local request_key = instance_id and instance_id > 0 and ("#" .. tostring(instance_id))
                      or ("id:" .. service.id)
  if stop_requested[request_key] then return true end
  if not app or not app.stop_service then return nil, "app.stop_service unavailable" end

  local call_ok, stopped, stop_error = pcall(function()
    return app.stop_service(target)
  end)
  if not call_ok or not stopped then
    return nil, tostring(call_ok and stop_error or stopped)
  end
  stop_requested[request_key] = true

  if restore_after_exit and not suspended_service_set[service.id] then
    suspended_service_set[service.id] = true
    suspended_service_ids[#suspended_service_ids + 1] = service.id
  end
  log("service stop requested", service.id, tostring(target))
  return true
end

local startup_wait_ms = 0
local hidpad_start_requested = false

local function startup_step()
  if exiting or game_started then return end
  if app and app.exiting and app.exiting() then
    request_exit("app exiting during startup")
    return
  end

  local services, list_error = list_running_services()
  if not services then
    startup_wait_ms = startup_wait_ms + APP.SERVICE_POLL_MS
    if startup_wait_ms >= APP.SERVICE_TIMEOUT_MS then
      log("service suspension failed", tostring(list_error))
      request_exit("service query timeout")
    end
    return
  end

  local hidpad_running = false
  local other_running = false
  for _, service in ipairs(services) do
    if type(service) == "table" and service.id == "hidpad" then
      hidpad_running = true
    elseif type(service) == "table" then
      other_running = true
      local stopped, stop_error = request_service_stop(service, false)
      if not stopped then
        log("service stop failed", tostring(service.id), tostring(stop_error))
        request_exit("service stop failed")
        return
      end
    end
  end

  if not other_running and not hidpad_running and not hidpad_start_requested then
    if not app or not app.start_service then
      log("hidpad service unavailable", "app.start_service unavailable")
      request_exit("hidpad unavailable")
      return
    end
    local call_ok, started, start_error = pcall(function()
      return app.start_service("hidpad")
    end)
    if not call_ok or not started then
      log("hidpad service unavailable", tostring(call_ok and start_error or started))
      request_exit("hidpad unavailable")
      return
    end
    hidpad_start_requested = true
    log("hidpad start requested")
  end

  if not other_running and hidpad_running then
    log("services suspended", tostring(#suspended_service_ids))
    start_game()
    return
  end

  startup_wait_ms = startup_wait_ms + APP.SERVICE_POLL_MS
  if startup_wait_ms >= APP.SERVICE_TIMEOUT_MS then
    log("service suspension timeout")
    request_exit("service suspension timeout")
  end
end

local function begin_startup()
  if not tmr or not tmr.create then
    log("service suspension unavailable", "tmr API unavailable")
    request_exit("tmr unavailable")
    return
  end

  local services, list_error = list_running_services()
  if not services then
    log("service snapshot failed", tostring(list_error))
    request_exit("service snapshot failed")
    return
  end

  for _, service in ipairs(services) do
    if type(service) == "table" and service.id ~= "hidpad" then
      local stopped, stop_error = request_service_stop(service, true)
      if not stopped then
        log("service stop failed", tostring(service.id), tostring(stop_error))
        request_exit("service stop failed")
        return
      end
    end
  end

  startup_timer = tmr.create()
  local timer_ok, timer_error = pcall(function()
    startup_timer:alarm(APP.SERVICE_POLL_MS, tmr.ALARM_AUTO or 1, startup_step)
  end)
  if not timer_ok then
    log("service poll timer failed", tostring(timer_error))
    request_exit("service poll timer failed")
    return
  end
  startup_step()
end

begin_startup()
