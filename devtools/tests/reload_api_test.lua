local main_path = assert(arg[1], "usage: lua reload_api_test.lua path/to/main.lua")
local host_loadfile = assert(loadfile)
local scheduled_timers = {}
local routes = {}

local function device_loadfile(path)
  if path == "/sd/apps/devtools/main.lua" then
    path = main_path
  end
  return host_loadfile(path)
end

loadfile = device_loadfile
json = { encode = function() return "{\"ok\":true}" end }
app = {
  route_base = function() return "/file" end,
  list = function() return {} end,
  rescan = function() return true end,
  launch = function() return true end,
  start_service = function(id)
    assert(id == "devtools")
    assert(device_loadfile("/sd/apps/devtools/main.lua"))()
    return true
  end
}
file = {
  stat = function(path)
    if path == "/sd/apps/devtools/main.lua" or path == "/sd/apps/devrun/app.info" or path == "/sd/apps/devrun/main.lua" then
      return { size = 1, is_dir = false }
    end
    return nil
  end,
  mkdir = function() return true end,
  putcontents = function() return true end,
  listdir = function() return {} end
}
httpd = {
  GET = "GET",
  POST = "POST",
  PUT = "PUT",
  DELETE = "DELETE",
  INDEX_NONE = 0,
  start = function() return true end,
  dynamic = function(method, route, handler)
    routes[method .. " " .. route] = handler
    return nil
  end,
  unregister = function(method, route)
    routes[method .. " " .. route] = nil
    return true
  end
}
tmr = {
  ALARM_SINGLE = 0,
  now = function() return 123456 + (#scheduled_timers * 1000) end,
  create = function()
    local timer = { stopped = false, unregistered = false }
    function timer:alarm(delay, mode, callback)
      self.delay = delay
      self.mode = mode
      self.callback = callback
    end
    function timer:stop() self.stopped = true end
    function timer:unregister() self.unregistered = true end
    scheduled_timers[#scheduled_timers + 1] = timer
    return timer
  end
}

assert(host_loadfile(main_path))()
local first = assert(DEVTOOLS)
assert(type(first.VERSION) == "string" and #first.VERSION > 0, "DEVTOOLS.VERSION must be a non-empty string")
assert(first.generation == 1)
assert(routes["POST /devtools/api/reload"] == first.api_reload)

loadfile = function(path)
  if path == "/sd/apps/devtools/main.lua" then
    return nil, "synthetic syntax error"
  end
  return device_loadfile(path)
end
local rejected = first.api_reload()
assert(rejected.status == "422 Unprocessable Entity")
assert(first.reload_pending == false)
assert(#scheduled_timers == 0)

loadfile = device_loadfile
local accepted = first.api_reload()
assert(accepted.status == "202 Accepted")
assert(first.reload_pending == true)
assert(#scheduled_timers == 1)
assert(type(scheduled_timers[1].callback) == "function")
assert(DEVTOOLS == first, "reload must not run inside the request handler")
local duplicate = first.api_reload()
assert(duplicate.status == "409 Conflict")
assert(#scheduled_timers == 1)

scheduled_timers[1].callback()
local second = assert(DEVTOOLS)
assert(second ~= first)
assert(first.shutting_down == true)
assert(second.generation == 2)
assert(second.reload_pending == false)
assert(routes["POST /devtools/api/reload"] == second.api_reload)
assert(scheduled_timers[1].unregistered == true)

print("reload API test OK")
