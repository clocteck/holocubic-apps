local M = {}

local APP_ID = "assistant"
local APP_DIR = "/sd/apps/" .. APP_ID
local MEMO_FILE = APP_DIR .. "/memos.json"

local DEFAULT_MEMOS = {
  "项目复盘",
  "阅读二十分钟",
  "散步放松",
}

M.tools = {
  {
    name = "memo.get",
    description = "读取 time-calendar-weather-memo 应用当前保存的三条备忘录内容。",
    inputSchema = {
      type = "object",
      additionalProperties = false,
    },
  },
  {
    name = "memo.set",
    description = "修改 time-calendar-weather-memo 应用的一条备忘录。index 为 1 到 3。",
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

local function write_text(path, body)
  if not file or not file.open then
    return nil, "file api unavailable"
  end
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

local function read_memos()
  local raw = read_text(MEMO_FILE)
  local doc = decode_json(raw)
  local exists = type(raw) == "string"
  if type(doc) == "table" and type(doc.memos) == "table" then
    return normalize_memos(doc.memos), exists
  end
  return normalize_memos(nil), exists
end

local function save_memos(memos)
  local body, enc_err = encode_json({ memos = normalize_memos(memos) })
  if not body then
    return nil, enc_err
  end
  local ok, write_err = write_text(MEMO_FILE, body)
  if not ok then
    return nil, write_err
  end
  return true
end

local function result(memos, existed)
  return {
    app_id = APP_ID,
    path = MEMO_FILE,
    existed = existed and true or false,
    memos = memos,
  }
end

M.handlers = {
  ["memo.get"] = function(arguments, ctx)
    local memos, existed = read_memos()
    return ctx.text_result(result(memos, existed))
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
    local memos = read_memos()
    memos[index] = arguments.text
    local ok, err = save_memos(memos)
    if not ok then
      return ctx.error_result(err)
    end
    return ctx.text_result(result(memos, true))
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
