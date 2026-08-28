local M = {}

local APP_ID = "time-calendar-weather-memo"
local APP_DIR = "/sd/apps/" .. APP_ID
local APP_INFO = APP_DIR .. "/app.info"
local MEMO_FILE = APP_DIR .. "/memos.json"
local INSTALL_ERROR = "请先安装备忘录 App（time-calendar-weather-memo）"

local DEFAULT_MEMOS = {
  "",
  "",
  "",
}

M.tools = {
  {
    name = "memo.get",
    description = "查看、读取或列出备忘录 App 当前保存的三条内容。当用户询问“查看备忘录”“备忘录里有什么”“记事本内容”或“我记了什么”时必须调用本工具，并以设备文件中的结果为准。",
    inputSchema = {
      type = "object",
      additionalProperties = false,
    },
  },
  {
    name = "memo.add",
    description = "向备忘录 App 添加或新建一条内容。当用户要求“添加备忘录”“记一下”或“新建记事”时调用；写入第一条空白位置，三条都已有内容时应先删除或修改。",
    inputSchema = {
      type = "object",
      properties = {
        text = { type = "string", description = "新备忘录内容。" },
      },
      required = { "text" },
      additionalProperties = false,
    },
  },
  {
    name = "memo.set",
    description = "修改或替换备忘录 App 中指定的一条内容。当用户要求修改第几条备忘录时调用，index 为 1 到 3。",
    inputSchema = {
      type = "object",
      properties = {
        index = {
          type = "integer",
          minimum = 1,
          maximum = 3,
          description = "要修改的备忘录序号，范围 1 到 3。",
        },
        text = {
          type = "string",
          description = "新的备忘录内容。",
        },
      },
      required = { "index", "text" },
      additionalProperties = false,
    },
  },
  {
    name = "memo.delete",
    description = "删除或清空备忘录 App 中指定序号的内容。当用户要求删除第几条备忘录时调用，index 为 1 到 3。",
    inputSchema = {
      type = "object",
      properties = {
        index = {
          type = "integer",
          minimum = 1,
          maximum = 3,
          description = "要删除的备忘录序号，范围 1 到 3。",
        },
      },
      required = { "index" },
      additionalProperties = false,
    },
  },
  {
    name = "memo.set_all",
    description = "一次性替换 time-calendar-weather-memo 应用的三条备忘录内容。",
    inputSchema = {
      type = "object",
      properties = {
        memos = {
          type = "array",
          minItems = 1,
          maxItems = 3,
          items = { type = "string" },
          description = "新的备忘录列表，最多三条；未提供的位置会写为空字符串。",
        },
      },
      required = { "memos" },
      additionalProperties = false,
    },
  },
}

local function codec()
  return rawget(_G, "json") or rawget(_G, "sjson")
end

local function decode_json(raw)
  local c = codec()
  if type(raw) ~= "string" or raw == "" or not c or not c.decode then
    return nil
  end
  local ok, value = pcall(c.decode, raw)
  if ok and type(value) == "table" then
    return value
  end
  return nil
end

local function encode_json(value)
  local c = codec()
  if not c or not c.encode then
    return nil, "json encoder unavailable"
  end
  local ok, raw = pcall(c.encode, value)
  if ok and type(raw) == "string" then
    return raw
  end
  return nil, tostring(raw or "json encode failed")
end

local function read_text(path)
  if file and file.getcontents then
    local ok, raw = pcall(file.getcontents, path)
    if ok and type(raw) == "string" then
      return raw
    end
  end
  local fd = file and file.open and file.open(path, "r")
  if not fd then
    return nil
  end
  local raw = fd:read(8192)
  fd:close()
  return raw
end

local function path_exists(path)
  if file and file.exists then
    local ok, exists = pcall(function() return file.exists(path) end)
    if ok then return exists == true end
  end
  if file and file.stat then
    local ok, stat = pcall(function() return file.stat(path) end)
    if ok then return stat ~= nil and stat ~= false end
  end
  return read_text(path) ~= nil
end

local function app_installed()
  return path_exists(APP_INFO)
end

local function write_text(path, body)
  if not file then
    return nil, "file api unavailable"
  end
  if file.putcontents then
    local ok, saved = pcall(function() return file.putcontents(path, body) end)
    if ok and saved then return true end
  end
  if not file.open then return nil, "file api unavailable" end
  local fd = file.open(path, "w+")
  if not fd then
    return nil, "failed to open memo file for writing"
  end
  local ok, err = pcall(function()
    fd:write(body)
    if fd.flush then fd:flush() end
  end)
  pcall(function() fd:close() end)
  if not ok then
    return nil, tostring(err or "failed to write memo file")
  end
  return true
end

local function normalize_memos(value)
  local out = {}
  for i = 1, 3 do
    local text = type(value) == "table" and value[i] or nil
    if type(text) ~= "string" then
      text = DEFAULT_MEMOS[i] or ""
    end
    out[i] = text
  end
  return out
end

local reload_error_reported = false

local function notify_calendar_reload()
  if not ipc or not ipc.send then
    if not reload_error_reported then
      reload_error_reported = true
      print("[xiaozhi] ERROR: calendar memo reload IPC unavailable; memo was saved but the UI may remain stale")
    end
    return false
  end
  local ok, sent, send_err = pcall(function()
    return ipc.send(APP_ID, "memos.reload", "{}")
  end)
  if not ok or not sent then
    if not reload_error_reported then
      reload_error_reported = true
      print("[xiaozhi] ERROR: calendar memo reload IPC failed: "
        .. tostring((ok and send_err) or sent or "endpoint unavailable")
        .. "; memo was saved but the UI may remain stale")
    end
    return false
  end
  reload_error_reported = false
  return true
end

local function read_memos()
  if not app_installed() then
    return nil, false, INSTALL_ERROR
  end
  local raw = read_text(MEMO_FILE)
  if raw == nil then
    local memos = normalize_memos(nil)
    local body, enc_err = encode_json({ memos = memos })
    if not body then return nil, false, enc_err end
    local ok, write_err = write_text(MEMO_FILE, body)
    if not ok then return nil, false, write_err end
    notify_calendar_reload()
    return memos, false
  end
  local doc = decode_json(raw)
  local exists = type(raw) == "string"
  if type(doc) == "table" and type(doc.memos) == "table" then
    return normalize_memos(doc.memos), exists
  end
  return nil, exists, "备忘录数据格式错误，请在备忘录 App 中重新保存"
end

local function save_memos(memos)
  if not app_installed() then return nil, INSTALL_ERROR end
  local body, enc_err = encode_json({ memos = normalize_memos(memos) })
  if not body then
    return nil, enc_err
  end
  local ok, write_err = write_text(MEMO_FILE, body)
  if not ok then
    return nil, write_err
  end
  notify_calendar_reload()
  return true
end

local function result(memos, existed, extra)
  local out = {
    app_id = APP_ID,
    path = MEMO_FILE,
    installed = true,
    existed = existed and true or false,
    memos = memos,
  }
  if type(extra) == "table" then
    for key, value in pairs(extra) do out[key] = value end
  end
  return out
end

M.handlers = {
  ["memo.get"] = function(arguments, ctx)
    local memos, existed, err = read_memos()
    if not memos then return ctx.error_result(err) end
    return ctx.text_result(result(memos, existed))
  end,

  ["memo.add"] = function(arguments, ctx)
    arguments = type(arguments) == "table" and arguments or {}
    if type(arguments.text) ~= "string" or arguments.text == "" then
      return ctx.error_result("text must be a non-empty string")
    end
    local memos, _, read_err = read_memos()
    if not memos then return ctx.error_result(read_err) end
    local index = nil
    for i = 1, 3 do
      if memos[i] == "" then index = i; break end
    end
    if not index then return ctx.error_result("三条备忘录已满，请先删除或指定序号修改") end
    memos[index] = arguments.text
    local ok, err = save_memos(memos)
    if not ok then return ctx.error_result(err) end
    return ctx.text_result(result(memos, true, { index = index, created = true }))
  end,

  ["memo.set"] = function(arguments, ctx)
    arguments = type(arguments) == "table" and arguments or {}
    local index = tonumber(arguments.index)
    if not index or index < 1 or index > 3 or index ~= math.floor(index) then
      return ctx.error_result("index must be an integer from 1 to 3")
    end
    if type(arguments.text) ~= "string" then
      return ctx.error_result("text must be a string")
    end
    local memos, _, read_err = read_memos()
    if not memos then return ctx.error_result(read_err) end
    memos[index] = arguments.text
    local ok, err = save_memos(memos)
    if not ok then
      return ctx.error_result(err)
    end
    return ctx.text_result(result(memos, true, { index = index }))
  end,

  ["memo.delete"] = function(arguments, ctx)
    arguments = type(arguments) == "table" and arguments or {}
    local index = tonumber(arguments.index)
    if not index or index < 1 or index > 3 or index ~= math.floor(index) then
      return ctx.error_result("index must be an integer from 1 to 3")
    end
    local memos, _, read_err = read_memos()
    if not memos then return ctx.error_result(read_err) end
    local deleted = memos[index] ~= ""
    memos[index] = ""
    local ok, err = save_memos(memos)
    if not ok then return ctx.error_result(err) end
    return ctx.text_result(result(memos, true, { index = index, deleted = deleted }))
  end,

  ["memo.set_all"] = function(arguments, ctx)
    arguments = type(arguments) == "table" and arguments or {}
    if type(arguments.memos) ~= "table" then
      return ctx.error_result("memos must be an array")
    end
    local memos = {}
    for i = 1, 3 do
      local text = arguments.memos[i]
      if text ~= nil and type(text) ~= "string" then
        return ctx.error_result("memo item " .. tostring(i) .. " must be a string")
      end
      memos[i] = text or ""
    end
    local ok, err = save_memos(memos)
    if not ok then
      return ctx.error_result(err)
    end
    return ctx.text_result(result(memos, true))
  end,
}

return M
