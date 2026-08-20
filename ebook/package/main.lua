local current = app and app.current and app.current()
local entry = current and current.entry or "/sd/apps/ebook/main.lua"
local dir = tostring(entry):gsub("\\", "/"):match("^(.*)/[^/]+$") or "/sd/apps/ebook"
local error_path = "/sd/ebooks/.last_error.txt"

local function save_error(message)
  message = tostring(message or "unknown reader error")
  if file and file.putcontents then
    pcall(file.putcontents, error_path, message)
  elseif file and file.open then
    local fd = file.open(error_path, "w+")
    if fd then pcall(function() fd:write(message) fd:flush() fd:close() end) end
  end
  print("[ebook]", message)
end

local chunk, compile_error = loadfile(dir .. "/reader.lua")
if type(chunk) ~= "function" then
  save_error("compile: " .. tostring(compile_error or chunk))
  error(compile_error or "reader.lua compile failed")
end

local ok, result = pcall(chunk)
if not ok then
  save_error("runtime: " .. tostring(result))
  error(result)
end

if file and file.remove then pcall(file.remove, error_path) end
return result
