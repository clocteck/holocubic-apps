local M = {}

local function encode(value)
  if not sjson or not sjson.encode then
    return nil, "json encoder unavailable"
  end
  local ok, result = pcall(sjson.encode, value)
  if not ok then
    return nil, tostring(result)
  end
  return result
end

local function decode(raw)
  if type(raw) ~= "string" or raw == "" or not sjson or not sjson.decode then
    return nil
  end
  local ok, result = pcall(sjson.decode, raw)
  if ok and type(result) == "table" then
    return result
  end
  return nil
end

local function text_result(value)
  local text, err = encode(value)
  if not text then
    text = tostring(err)
  end
  return { content = { { type = "text", text = text } } }
end

local function error_result(message)
  return {
    content = { { type = "text", text = tostring(message or "unknown error") } },
    isError = true,
  }
end

local function result_from_plugin(value, err)
  if value == false or value == nil then
    return error_result(err or "plugin returned no result")
  end
  if type(value) == "table" and type(value.content) == "table" then
    return value
  end
  return text_result(value)
end

local function is_array(value)
  if type(value) ~= "table" then return false end
  local n = #value
  if n == 0 then return false end
  for i = 1, n do
    if value[i] == nil then return false end
  end
  return true
end

local function valid_tool_name(name)
  return type(name) == "string" and name ~= "" and #name <= 96 and name:match("^[%w_.%-]+$") ~= nil
end

local function valid_plugin_file(name)
  return type(name) == "string"
    and name:match("%.lua$") ~= nil
    and name ~= "init.lua"
    and name:match("^[%w_.%-]+%.lua$") ~= nil
end

local function list_lua_files(dir)
  local out = {}
  if not file then
    return out, "file api unavailable"
  end

  local ok, list = false, nil
  if file.listdir then
    ok, list = pcall(file.listdir, dir)
    if (not ok or type(list) ~= "table") and not dir:match("/$") then
      ok, list = pcall(file.listdir, dir .. "/")
    end
  end
  if (not ok or type(list) ~= "table") and file.list then
    ok, list = pcall(file.list, dir)
    if (not ok or type(list) ~= "table") and not dir:match("/$") then
      ok, list = pcall(file.list, dir .. "/")
    end
  end
  if not ok or type(list) ~= "table" then
    return out, "file.list unavailable"
  end
  local seen = {}
  for key, item in pairs(list) do
    local name = nil
    local is_dir = false
    if type(item) == "string" then
      name = item
    elseif type(item) == "table" then
      name = item.name or item.filename or item[1]
      is_dir = item.is_dir or item.type == "dir" or item.directory
    elseif type(key) == "string" then
      name = key
    end
    if type(name) == "string" then
      name = name:match("([^/\\]+)$") or name
    end
    if not is_dir and valid_plugin_file(name) and not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

local function add_tool(registry, tool, handler, source)
  if type(tool) ~= "table" or not valid_tool_name(tool.name) then
    return false, "invalid tool definition"
  end
  if type(handler) ~= "function" then
    return false, "missing handler for " .. tostring(tool.name)
  end
  if registry.handlers[tool.name] then
    return false, "duplicate tool: " .. tool.name
  end
  registry.tools[#registry.tools + 1] = tool
  registry.handlers[tool.name] = handler
  registry.sources[tool.name] = source or "plugin"
  return true
end

local function plugin_tool_list(plugin)
  if type(plugin.tools) == "table" then
    return is_array(plugin.tools) and plugin.tools or { plugin.tools }
  end
  if type(plugin.tool) == "table" then
    return { plugin.tool }
  end
  if valid_tool_name(plugin.name) then
    return {
      {
        name = plugin.name,
        description = tostring(plugin.description or ""),
        inputSchema = type(plugin.inputSchema) == "table" and plugin.inputSchema
          or { type = "object", properties = {}, additionalProperties = true },
      },
    }
  end
  return {}
end

local function plugin_handler(plugin, name)
  local handlers = type(plugin.handlers) == "table" and plugin.handlers or nil
  if handlers and type(handlers[name]) == "function" then
    return handlers[name]
  end
  if type(plugin.call) == "function" then
    return plugin.call
  end
  return nil
end

function M.new(cfg, send_payload, before_app_exit)
  local self = {
    cfg = cfg,
    send_payload = send_payload,
    before_app_exit = before_app_exit,
  }

  local function send(message)
    local raw, err = encode(message)
    if not raw then
      print("[xiaozhi] mcp encode failed", tostring(err))
      return false
    end
    return self.send_payload(raw)
  end

  local registry = {
    tools = {},
    handlers = {},
    sources = {},
  }

  local function tool_context(extra)
    local ctx = {
      cfg = cfg,
      encode = encode,
      text_result = text_result,
      error_result = error_result,
      before_app_exit = self.before_app_exit,
    }
    if type(extra) == "table" then
      for k, v in pairs(extra) do
        ctx[k] = v
      end
    end
    return ctx
  end

  local function load_plugins()
    local dir = cfg.MCP_DIR or ((cfg.APP_DIR or "/sd/apps/xiaozhi-service") .. "/mcp")
    local names, err = list_lua_files(dir)
    if err then
      print("[xiaozhi] mcp plugin scan skipped", tostring(err))
      names = {}
    end
    local ctx = tool_context()
    for i = 1, #names do
      local path = dir .. "/" .. names[i]
      local ok, plugin = pcall(dofile, path)
      if not ok or type(plugin) ~= "table" then
        print("[xiaozhi] mcp plugin load failed", path, tostring(plugin))
      else
        if type(plugin.init) == "function" then
          local init_ok, init_err = pcall(plugin.init, ctx)
          if not init_ok then
            print("[xiaozhi] mcp plugin init failed", path, tostring(init_err))
          end
        end
        local tools = plugin_tool_list(plugin)
        for j = 1, #tools do
          local tool = tools[j]
          local handler = plugin_handler(plugin, tool.name)
          local add_ok, add_err = add_tool(registry, tool, handler, names[i])
          if add_ok then
            print("[xiaozhi] mcp plugin tool", names[i], tool.name)
          else
            print("[xiaozhi] mcp plugin skipped", names[i], tostring(add_err))
          end
        end
      end
    end
  end

  load_plugins()

  local function call_tool(name, arguments)
    arguments = type(arguments) == "table" and arguments or {}
    local handler = registry.handlers[name]
    if handler then
      local ok, result, err = pcall(handler, arguments, tool_context({
        name = name,
        source = registry.sources[name],
      }))
      if not ok then
        return error_result(result)
      end
      return result_from_plugin(result, err)
    end
    return error_result("unknown tool: " .. tostring(name))
  end

  function self:handle(payload)
    if type(payload) == "string" then
      payload = decode(payload)
    end
    if type(payload) ~= "table" then return false end
    local method = payload.method
    local id = payload.id
    if method == "notifications/initialized" then return true end
    if id == nil then return false end

    local result
    if method == "initialize" then
      result = {
        protocolVersion = "2024-11-05",
        capabilities = { tools = { listChanged = false } },
        serverInfo = { name = "holocubic-device", version = tostring(cfg.VERSION or "1.0") },
      }
    elseif method == "tools/list" then
      result = { tools = registry.tools }
    elseif method == "tools/call" then
      local params = type(payload.params) == "table" and payload.params or {}
      result = call_tool(params.name, params.arguments)
    else
      return send({ jsonrpc = "2.0", id = id, error = { code = -32601, message = "Method not found" } })
    end
    return send({ jsonrpc = "2.0", id = id, result = result })
  end

  return self
end

return M
