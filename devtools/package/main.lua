-- DevTools service: SD file manager + dedicated DevRun code runner.

if _G.DEVTOOLS and _G.DEVTOOLS.stop then
  pcall(function() _G.DEVTOOLS.stop("reload") end)
end

DEVTOOLS = {}
local APP = DEVTOOLS

APP.VERSION = "2026-05-09-devtools-v1"
APP.ROOT_PATH = "/sd"
APP.APPS_PATH = "/sd/apps"
APP.RUN_APP_ID = "devrun"
APP.RUN_APP_DIR = "/sd/apps/devrun"
APP.RUN_APP_MAIN = "/sd/apps/devrun/main.lua"
APP.RUN_APP_INFO = "/sd/apps/devrun/app.info"
APP.MAX_FILE_SIZE = 8 * 1024 * 1024
APP.CHUNK_SIZE = 64 * 1024
APP.PREVIEW_TEXT_LIMIT = 256 * 1024
APP.PREVIEW_MEDIA_LIMIT = 3 * 1024 * 1024
APP.MAX_CODE_BYTES = 192 * 1024
APP.LEGACY_ROUTE_BASE = app.route_base() or "/file"
APP.ROUTE_BASE = "/devtools"
APP.API_PREFIX = APP.ROUTE_BASE .. "/api"
APP.routes = {}
APP.logs = {}
APP.request_count = 0
APP.last_action = "idle"
APP.shutting_down = false

local function text_or(value, fallback)
  if value == nil then
    return fallback or ""
  end
  local text = tostring(value)
  if text == "" then
    return fallback or ""
  end
  return text
end

local function starts_with(text, prefix)
  text = text_or(text, "")
  prefix = text_or(prefix, "")
  if prefix == "" then
    return true
  end
  return text:sub(1, #prefix) == prefix
end

local function url_decode(text)
  text = text_or(text, "")
  text = text:gsub("+", " ")
  text = text:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  return text
end

local function parse_query(query)
  local out = {}
  local text = text_or(query, "")
  for pair in text:gmatch("([^&]+)") do
    local key, value = pair:match("^([^=]*)=(.*)$")
    if not key then
      key = pair
      value = ""
    end
    out[url_decode(key)] = url_decode(value)
  end
  return out
end

local function json_response(status, value)
  local ok, raw, err = pcall(function()
    return json.encode(value)
  end)
  if not ok or not raw then
    status = "500 Internal Server Error"
    raw = string.format("{\"ok\":false,\"error\":%q}", text_or(err, "json encode failed"))
  end
  return {
    status = status or "200 OK",
    type = "application/json; charset=utf-8",
    headers = {
      ["cache-control"] = "no-store",
      ["connection"] = "close"
    },
    body = raw
  }
end

local function text_response(status, content_type, body, headers)
  if type(headers) ~= "table" then
    headers = {}
  end
  headers["cache-control"] = headers["cache-control"] or "no-store"
  headers["connection"] = headers["connection"] or "close"
  return {
    status = status or "200 OK",
    type = content_type or "text/plain; charset=utf-8",
    headers = headers,
    body = text_or(body, "")
  }
end

local function error_response(status, message)
  return json_response(status or "400 Bad Request", {
    ok = false,
    error = text_or(message, "request failed")
  })
end

local function mark_action(action, path)
  APP.request_count = APP.request_count + 1
  APP.last_action = text_or(action, "idle")
  local line = APP.last_action
  if path and path ~= "" then
    line = line .. " " .. tostring(path)
  end
  if #line > 38 then
    line = line:sub(1, 38)
  end
  table.insert(APP.logs, 1, line)
  while #APP.logs > 3 do
    table.remove(APP.logs)
  end
end

local function split_path(path)
  local parts = {}
  for part in text_or(path, ""):gmatch("[^/]+") do
    parts[#parts + 1] = part
  end
  return parts
end

local function path_starts_with_root(path)
  return path == APP.ROOT_PATH or path:sub(1, #APP.ROOT_PATH + 1) == (APP.ROOT_PATH .. "/")
end

local function normalize_sd_path(path)
  path = text_or(path, "")
  if path == "" then
    path = APP.ROOT_PATH
  end
  path = path:gsub("\\", "/")
  if path:sub(1, 1) ~= "/" then
    path = APP.ROOT_PATH .. "/" .. path
  elseif not path_starts_with_root(path) then
    path = APP.ROOT_PATH .. path
  end

  local raw_parts = split_path(path)
  local parts = {}
  for i = 1, #raw_parts do
    local part = raw_parts[i]
    if part == "" or part == "." then
      -- skip
    elseif part == ".." then
      if #parts <= 1 then
        return nil, "path out of range"
      end
      table.remove(parts)
    else
      parts[#parts + 1] = part
    end
  end

  if #parts == 0 then
    return APP.ROOT_PATH
  end
  if parts[1] ~= "sd" then
    return nil, "path must stay under /sd"
  end
  return "/" .. table.concat(parts, "/")
end

local function basename(path)
  local normalized = normalize_sd_path(path or "")
  if not normalized then
    return ""
  end
  if normalized == APP.ROOT_PATH then
    return "sd"
  end
  local parts = split_path(normalized)
  return parts[#parts] or ""
end

local function dirname(path)
  local normalized = normalize_sd_path(path or "")
  if not normalized or normalized == APP.ROOT_PATH then
    return APP.ROOT_PATH
  end
  local parts = split_path(normalized)
  if #parts <= 1 then
    return APP.ROOT_PATH
  end
  table.remove(parts)
  return "/" .. table.concat(parts, "/")
end

local function ext_lower(path)
  local name = basename(path):lower()
  return name:match("%.([%w_%-]+)$") or ""
end

local function guess_mime(path)
  local ext = ext_lower(path)
  local map = {
    txt = "text/plain; charset=utf-8",
    lua = "text/plain; charset=utf-8",
    log = "text/plain; charset=utf-8",
    json = "application/json; charset=utf-8",
    csv = "text/csv; charset=utf-8",
    md = "text/markdown; charset=utf-8",
    ini = "text/plain; charset=utf-8",
    cfg = "text/plain; charset=utf-8",
    xml = "application/xml; charset=utf-8",
    html = "text/html; charset=utf-8",
    htm = "text/html; charset=utf-8",
    css = "text/css; charset=utf-8",
    js = "application/javascript; charset=utf-8",
    gif = "image/gif",
    png = "image/png",
    jpg = "image/jpeg",
    jpeg = "image/jpeg",
    bmp = "image/bmp",
    webp = "image/webp",
    svg = "image/svg+xml",
    mp3 = "audio/mpeg",
    wav = "audio/wav",
    ogg = "audio/ogg",
    mp4 = "video/mp4",
    mov = "video/quicktime",
    zip = "application/zip",
    gz = "application/gzip",
    bin = "application/octet-stream"
  }
  return map[ext] or "application/octet-stream"
end

local function category_of(path, is_dir)
  if is_dir then
    return "dir"
  end
  local ext = ext_lower(path)
  if ext == "gif" or ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "bmp" or ext == "webp" or ext == "svg" then
    return "image"
  end
  if ext == "txt" or ext == "lua" or ext == "json" or ext == "csv" or ext == "md" or ext == "log" or ext == "ini" or ext == "cfg" or ext == "xml" or ext == "html" or ext == "htm" or ext == "css" or ext == "js" then
    return "text"
  end
  if ext == "mp3" or ext == "wav" or ext == "ogg" then
    return "audio"
  end
  if ext == "mp4" or ext == "mov" then
    return "video"
  end
  if ext == "zip" or ext == "gz" then
    return "archive"
  end
  return "binary"
end

local function to_int(value, default_value)
  local n = tonumber(value)
  if not n then
    return default_value
  end
  return math.floor(n)
end

local function is_root_path(path)
  return text_or(path, "") == APP.ROOT_PATH
end

local function is_true(value)
  value = text_or(value, ""):lower()
  return value == "1" or value == "true" or value == "yes" or value == "on"
end

local function ensure_parent_dir(path)
  local parent = dirname(path)
  local st = file.stat(parent)
  if not st or not st.is_dir then
    return false, "parent directory missing"
  end
  return true
end

local function safe_chunk_size(n)
  n = to_int(n, APP.CHUNK_SIZE)
  if not n or n <= 0 then
    n = APP.CHUNK_SIZE
  end
  if n > APP.CHUNK_SIZE then
    n = APP.CHUNK_SIZE
  end
  return n
end

local function list_dir(path)
  local items = {}
  local list = file.listdir(path) or {}
  for i = 1, #list do
    local entry = list[i]
    local entry_path = entry.path or (path == APP.ROOT_PATH and (APP.ROOT_PATH .. "/" .. text_or(entry.name, "")) or (path .. "/" .. text_or(entry.name, "")))
    items[#items + 1] = {
      name = text_or(entry.name, ""),
      path = entry_path,
      size = entry.size or 0,
      is_dir = entry.is_dir and true or false,
      ext = ext_lower(entry_path),
      mime = guess_mime(entry_path),
      category = category_of(entry_path, entry.is_dir and true or false)
    }
  end
  table.sort(items, function(a, b)
    if a.is_dir ~= b.is_dir then
      return a.is_dir
    end
    return text_or(a.name, ""):lower() < text_or(b.name, ""):lower()
  end)
  return items
end

local function read_request_body(req, max_bytes)
  local parts = {}
  local total = 0
  while true do
    local chunk = req.getbody()
    if not chunk then
      break
    end
    total = total + #chunk
    if max_bytes and total > max_bytes then
      return nil, "request body too large"
    end
    parts[#parts + 1] = chunk
  end
  return table.concat(parts)
end

local function read_file_chunk(path, offset, size)
  local st = file.stat(path)
  if not st then
    return nil, "not found"
  end
  if st.is_dir then
    return nil, "path is directory"
  end
  offset = to_int(offset, 0)
  size = safe_chunk_size(size)
  if offset < 0 then
    return nil, "invalid offset"
  end
  if offset > (st.size or 0) then
    return nil, "offset out of range"
  end

  local fd = file.open(path, "r")
  if not fd then
    return nil, "open failed"
  end
  if offset > 0 then
    local pos = fd:seek("set", offset)
    if not pos then
      fd:close()
      return nil, "seek failed"
    end
  end
  local chunk = fd:read(size) or ""
  fd:close()
  local next_offset = offset + #chunk
  return {
    chunk = chunk,
    next_offset = next_offset,
    eof = next_offset >= (st.size or 0),
    size = st.size or 0,
    mime = guess_mime(path),
    name = basename(path)
  }
end

local function remove_tree(path)
  local normalized, err = normalize_sd_path(path or "")
  if not normalized then
    return false, err
  end
  if is_root_path(normalized) then
    return false, "can not remove /sd"
  end
  local st = file.stat(normalized)
  if not st then
    return false, "path not found"
  end
  if not st.is_dir then
    file.remove(normalized)
    if file.stat(normalized) then
      return false, "remove failed: " .. normalized
    end
    return true
  end
  local list = file.listdir(normalized) or {}
  for i = 1, #list do
    local entry = list[i]
    local child_path = entry.path or (normalized .. "/" .. text_or(entry.name, ""))
    local ok, rm_err = remove_tree(child_path)
    if not ok then
      return false, rm_err
    end
  end
  local ok = file.rmdir(normalized)
  if not ok or file.stat(normalized) then
    return false, "rmdir failed: " .. normalized
  end
  return true
end

local function write_request_body_to_file(req, fd, base_offset, total_size)
  local written = 0
  while true do
    local chunk = req.getbody()
    if not chunk then
      break
    end
    local n = #chunk
    if n > 0 then
      if (base_offset + written + n) > total_size then
        return nil, "request body exceeds total size"
      end
      local ok = fd:write(chunk)
      if not ok then
        return nil, "file write failed"
      end
      written = written + n
    end
  end
  fd:flush()
  return written
end

local function prepare_upload_file(path, offset, total)
  if total < 0 then
    return nil, "invalid total size"
  end
  if total > APP.MAX_FILE_SIZE then
    return nil, "file too large"
  end
  if offset < 0 or offset > total then
    return nil, "invalid offset"
  end
  local ok_parent, parent_err = ensure_parent_dir(path)
  if not ok_parent then
    return nil, parent_err
  end
  local st = file.stat(path)
  if st and st.is_dir then
    return nil, "target path is directory"
  end
  if offset == 0 then
    return file.open(path, "w+")
  end
  if not st then
    return nil, "resume target missing"
  end
  if offset > (st.size or 0) then
    return nil, "offset beyond file size"
  end
  local fd = file.open(path, "r+")
  if not fd then
    return nil, "open for update failed"
  end
  local pos = fd:seek("set", offset)
  if not pos then
    fd:close()
    return nil, "seek failed"
  end
  return fd
end

local function sibling_path_with_name(path, name)
  local idx = text_or(path, ""):match("^.*()/")
  if not idx then
    return "/" .. text_or(name, "")
  end
  return path:sub(1, idx) .. text_or(name, "")
end

local function safe_remove(path)
  local st = file.stat(path)
  if not st then
    return true
  end
  local ok, result = pcall(function()
    return file.remove(path)
  end)
  return ok and result and true or false
end

local function safe_rename(src, dst)
  if src == dst then
    return true
  end
  local ok, result = pcall(function()
    return file.rename(src, dst)
  end)
  if not ok or not result then
    return nil, "rename failed"
  end
  return true
end

local function atomic_save_text(path, source)
  local tmp_path = sibling_path_with_name(path, "main.tmp")
  local bak_path = sibling_path_with_name(path, "main.bak")
  local had_original = file.stat(path) and true or false

  safe_remove(tmp_path)
  local ok_put, result_put = pcall(function()
    return file.putcontents(tmp_path, source)
  end)
  if not ok_put or not result_put then
    safe_remove(tmp_path)
    return nil, "write temp file failed"
  end

  if had_original then
    safe_remove(bak_path)
    local ok_bak, err_bak = safe_rename(path, bak_path)
    if not ok_bak then
      safe_remove(tmp_path)
      return nil, err_bak or "backup original file failed"
    end
  end

  local ok_swap, err_swap = safe_rename(tmp_path, path)
  if not ok_swap then
    safe_remove(tmp_path)
    if had_original then
      safe_rename(bak_path, path)
    end
    return nil, err_swap or "replace source file failed"
  end
  return true
end

local function ensure_run_app()
  file.mkdir(APP.APPS_PATH)
  file.mkdir(APP.RUN_APP_DIR)
  local info = "name = DevRun\nentry = main.lua\ndescription = Temporary developer run app\n"
  if not file.stat(APP.RUN_APP_INFO) then
    file.putcontents(APP.RUN_APP_INFO, info)
  end
  if not file.stat(APP.RUN_APP_MAIN) then
    local code = "if lv_obj_clean and lv_scr_act then lv_obj_clean(lv_scr_act()) end\n\nlocal root = lv_scr_act()\nlocal MAIN_STYLE = LV_PART_MAIN | LV_STATE_DEFAULT\n\nlv_obj_set_style_bg_color(root, 0x000000, MAIN_STYLE)\nlv_obj_set_style_bg_opa(root, 255, MAIN_STYLE)\n\nlocal label = lv_label_create(root)\nlv_label_set_text(label, \"Hello DevRun\")\nlv_obj_set_style_text_color(label, 0xFFFFFF, MAIN_STYLE)\nlv_obj_set_style_text_opa(label, 255, MAIN_STYLE)\nlv_obj_align(label, LV_ALIGN_CENTER, 0, 0)\n"
    file.putcontents(APP.RUN_APP_MAIN, code)
  end
end

local function editable_apps_snapshot()
  local ok, list = pcall(function()
    return app.list()
  end)
  if not ok or type(list) ~= "table" then
    return {}, ""
  end
  local out = {}
  local current_app_id = ""
  for _, item in ipairs(list) do
    if item and item.running and current_app_id == "" then
      current_app_id = text_or(item.id, "")
    end
    if item and item.source == "sd" and text_or(item.id, "") ~= "" then
      out[#out + 1] = {
        id = text_or(item.id, ""),
        name = text_or(item.name, text_or(item.id, "app")),
        source = text_or(item.source, ""),
        entry = text_or(item.entry, ""),
        running = item.running and true or false
      }
    end
  end
  table.sort(out, function(a, b)
    local an = text_or(a.name, a.id):lower()
    local bn = text_or(b.name, b.id):lower()
    if an == bn then
      return text_or(a.id, "") < text_or(b.id, "")
    end
    return an < bn
  end)
  return out, current_app_id
end

local function update_screen()
  -- Service apps do not own a LVGL screen. Keep this as a cheap stats hook.
end

local function set_status(text)
  APP.status = text_or(text, "ready")
  print("[devtools]", APP.status)
end

function APP.render_index_html()
  return APP.HTML:gsub("__APP_BASE__", APP.ROUTE_BASE):gsub("__RUN_APP_ID__", APP.RUN_APP_ID)
end

function APP.route_redirect()
  return text_response("302 Found", "text/plain; charset=utf-8", "", {
    ["location"] = APP.ROUTE_BASE .. "/"
  })
end

function APP.route_index()
  mark_action("open", APP.ROUTE_BASE)
  update_screen()
  return text_response("200 OK", "text/html; charset=utf-8", APP.render_index_html())
end

function APP.route_favicon()
  return text_response("204 No Content", "image/x-icon", "")
end

function APP.api_info()
  mark_action("info", "")
  update_screen()
  return json_response("200 OK", {
    ok = true,
    version = APP.VERSION,
    route_base = APP.ROUTE_BASE,
    root_path = APP.ROOT_PATH,
    chunk_size = APP.CHUNK_SIZE,
    max_file_size = APP.MAX_FILE_SIZE,
    preview_text_limit = APP.PREVIEW_TEXT_LIMIT,
    preview_media_limit = APP.PREVIEW_MEDIA_LIMIT,
    run_app_id = APP.RUN_APP_ID,
    run_app_main = APP.RUN_APP_MAIN,
    request_count = APP.request_count,
    last_action = APP.last_action
  })
end

function APP.api_list(req)
  local q = parse_query(req.query)
  local path, err = normalize_sd_path(q.path or APP.ROOT_PATH)
  if not path then
    return error_response("400 Bad Request", err)
  end
  local st = file.stat(path)
  if not st or not st.is_dir then
    return error_response("404 Not Found", "directory not found")
  end
  local items = list_dir(path)
  local dir_count, file_count, total_bytes = 0, 0, 0
  for i = 1, #items do
    if items[i].is_dir then
      dir_count = dir_count + 1
    else
      file_count = file_count + 1
      total_bytes = total_bytes + (items[i].size or 0)
    end
  end
  mark_action("list", path)
  update_screen()
  return json_response("200 OK", {
    ok = true,
    path = path,
    parent = dirname(path),
    dir_count = dir_count,
    file_count = file_count,
    total_bytes = total_bytes,
    items = items
  })
end

function APP.api_stat(req)
  local q = parse_query(req.query)
  local path, err = normalize_sd_path(q.path or "")
  if not path then
    return error_response("400 Bad Request", err)
  end
  local st = file.stat(path)
  if not st then
    return error_response("404 Not Found", "path not found")
  end
  mark_action("stat", path)
  update_screen()
  return json_response("200 OK", {
    ok = true,
    path = path,
    name = basename(path),
    parent = dirname(path),
    size = st.size or 0,
    is_dir = st.is_dir and true or false,
    ext = ext_lower(path),
    mime = guess_mime(path),
    category = category_of(path, st.is_dir and true or false)
  })
end

function APP.api_read(req)
  local q = parse_query(req.query)
  local path, err = normalize_sd_path(q.path or "")
  if not path then
    return error_response("400 Bad Request", err)
  end
  local info, read_err = read_file_chunk(path, q.offset, q.size)
  if not info then
    return error_response(read_err == "not found" and "404 Not Found" or "400 Bad Request", read_err or "read failed")
  end
  mark_action("read", basename(path))
  update_screen()
  return {
    status = "200 OK",
    type = info.mime,
    headers = {
      ["cache-control"] = "no-store",
      ["connection"] = "close",
      ["x-file-size"] = tostring(info.size or 0),
      ["x-next-offset"] = tostring(info.next_offset or 0),
      ["x-eof"] = info.eof and "1" or "0",
      ["x-file-name"] = info.name or ""
    },
    body = info.chunk
  }
end

function APP.api_mkdir(req)
  local q = parse_query(req.query)
  local path, err = normalize_sd_path(q.path or "")
  if not path then
    return error_response("400 Bad Request", err)
  end
  if is_root_path(path) then
    return error_response("400 Bad Request", "can not create /sd")
  end
  if file.stat(path) then
    return error_response("409 Conflict", "path already exists")
  end
  local ok_parent, parent_err = ensure_parent_dir(path)
  if not ok_parent then
    return error_response("400 Bad Request", parent_err)
  end
  if not file.mkdir(path) then
    return error_response("400 Bad Request", "mkdir failed")
  end
  mark_action("mkdir", path)
  update_screen()
  return json_response("200 OK", { ok = true, path = path })
end

function APP.api_rename(req)
  local q = parse_query(req.query)
  local path, err1 = normalize_sd_path(q.path or "")
  local new_path, err2 = normalize_sd_path(q.new_path or "")
  if not path then
    return error_response("400 Bad Request", err1)
  end
  if not new_path then
    return error_response("400 Bad Request", err2)
  end
  if is_root_path(path) or is_root_path(new_path) then
    return error_response("400 Bad Request", "can not rename /sd root")
  end
  if not file.stat(path) then
    return error_response("404 Not Found", "path not found")
  end
  local ok_parent, parent_err = ensure_parent_dir(new_path)
  if not ok_parent then
    return error_response("400 Bad Request", parent_err)
  end
  if file.stat(new_path) then
    return error_response("409 Conflict", "target path already exists")
  end
  if not file.rename(path, new_path) then
    return error_response("400 Bad Request", "rename failed")
  end
  mark_action("rename", basename(path))
  update_screen()
  return json_response("200 OK", { ok = true, path = path, new_path = new_path })
end

function APP.api_remove(req)
  local q = parse_query(req.query)
  local path, err = normalize_sd_path(q.path or "")
  if not path then
    return error_response("400 Bad Request", err)
  end
  if is_root_path(path) then
    return error_response("400 Bad Request", "can not remove /sd")
  end
  local st = file.stat(path)
  if not st then
    return error_response("404 Not Found", "file not found")
  end
  if st.is_dir then
    return error_response("400 Bad Request", "path is a directory")
  end
  file.remove(path)
  if file.stat(path) then
    return error_response("500 Internal Server Error", "remove failed")
  end
  mark_action("remove", basename(path))
  update_screen()
  return json_response("200 OK", { ok = true, path = path })
end

function APP.api_rmdir(req)
  local q = parse_query(req.query)
  local path, err = normalize_sd_path(q.path or "")
  if not path then
    return error_response("400 Bad Request", err)
  end
  if is_root_path(path) then
    return error_response("400 Bad Request", "can not remove /sd")
  end
  local st = file.stat(path)
  if not st then
    return error_response("404 Not Found", "directory not found")
  end
  if not st.is_dir then
    return error_response("400 Bad Request", "path is not a directory")
  end
  if is_true(q.recursive) then
    local ok_recursive, recursive_err = remove_tree(path)
    if not ok_recursive then
      return error_response("400 Bad Request", recursive_err or "recursive remove failed")
    end
    mark_action("rmtree", basename(path))
    update_screen()
    return json_response("200 OK", { ok = true, path = path, recursive = true })
  end
  if not file.rmdir(path) then
    return error_response("400 Bad Request", "directory not empty; use recursive=1")
  end
  mark_action("rmdir", basename(path))
  update_screen()
  return json_response("200 OK", { ok = true, path = path })
end

function APP.api_upload(req)
  local q = parse_query(req.query)
  local path, err = normalize_sd_path(q.path or "")
  if not path then
    return error_response("400 Bad Request", err)
  end
  if is_root_path(path) then
    return error_response("400 Bad Request", "can not write /sd root")
  end
  local offset = to_int(q.offset, 0)
  local total = to_int(q.total, -1)
  local fd, open_err = prepare_upload_file(path, offset, total)
  if not fd then
    return error_response(open_err == "file too large" and "413 Payload Too Large" or "400 Bad Request", open_err or "open failed")
  end
  if total == 0 and offset == 0 then
    fd:flush()
    fd:close()
    mark_action("upload", basename(path))
    update_screen()
    return json_response("200 OK", { ok = true, path = path, next_offset = 0, total = 0, done = true })
  end
  local written, write_err = write_request_body_to_file(req, fd, offset, total)
  fd:close()
  if not written then
    return error_response("400 Bad Request", write_err or "write failed")
  end
  local next_offset = offset + written
  local st = file.stat(path)
  if not st or st.is_dir then
    return error_response("500 Internal Server Error", "write result invalid")
  end
  mark_action("upload", basename(path))
  update_screen()
  return json_response("200 OK", {
    ok = true,
    path = path,
    next_offset = next_offset,
    total = total,
    done = next_offset >= total,
    size = st.size or 0
  })
end

function APP.api_apps()
  ensure_run_app()
  local apps, current_app_id = editable_apps_snapshot()
  mark_action("apps", "")
  update_screen()
  return json_response("200 OK", {
    ok = true,
    apps = apps,
    current_app_id = current_app_id ~= "" and current_app_id or nil,
    run_app_id = APP.RUN_APP_ID,
    run_app_main = APP.RUN_APP_MAIN
  })
end

function APP.api_read_run_code()
  ensure_run_app()
  local content = file.getcontents(APP.RUN_APP_MAIN)
  if content == nil then
    return error_response("500 Internal Server Error", "open DevRun source failed")
  end
  mark_action("read-code", APP.RUN_APP_ID)
  update_screen()
  return text_response("200 OK", "text/plain; charset=utf-8", content, {
    ["x-app-id"] = APP.RUN_APP_ID,
    ["x-app-entry"] = APP.RUN_APP_MAIN
  })
end

function APP.api_save_run_code(req, launch_after_save)
  ensure_run_app()
  local source, read_err = read_request_body(req, APP.MAX_CODE_BYTES)
  if source == nil then
    return error_response("400 Bad Request", read_err or "read request body failed")
  end
  local ok_save, save_err = atomic_save_text(APP.RUN_APP_MAIN, source)
  if not ok_save then
    return error_response("500 Internal Server Error", save_err or "save source failed")
  end

  local launched = false
  local rescan_requested = false
  if launch_after_save then
    pcall(function()
      app.rescan()
      rescan_requested = true
    end)
    local ok_launch, err_launch = app.launch(APP.RUN_APP_ID)
    if not ok_launch then
      return error_response("400 Bad Request", err_launch or "launch DevRun failed")
    end
    launched = true
  end
  mark_action(launch_after_save and "run-code" or "save-code", APP.RUN_APP_ID)
  update_screen()
  return json_response("200 OK", {
    ok = true,
    id = APP.RUN_APP_ID,
    entry = APP.RUN_APP_MAIN,
    bytes = #source,
    launched = launched,
    rescan_requested = rescan_requested
  })
end

function APP.route_save_code(req)
  return APP.api_save_run_code(req, false)
end

function APP.route_run_code(req)
  return APP.api_save_run_code(req, true)
end

APP.HTML = [==[
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Cubic DevTools</title>
<style>
:root{
  color-scheme:light;
  --bg:#f4f7fb;
  --surface:#ffffff;
  --surface-2:#f8fafc;
  --line:#d9e2ee;
  --text:#172131;
  --muted:#63748a;
  --accent:#2563eb;
  --accent-2:#0f766e;
  --danger:#c2415b;
  --warn:#b46a13;
  --ok:#167452;
  --code-bg:#101825;
  --code-line:#263247;
  --code-text:#dce7f7;
  --shadow:0 14px 38px rgba(21,35,58,.08);
  --mono:"Cascadia Code","JetBrains Mono","Consolas","SFMono-Regular",monospace;
  --sans:"Aptos","PingFang SC","Microsoft YaHei",sans-serif;
}
*{box-sizing:border-box}
html,body{min-height:100%}
body{
  margin:0;
  background:linear-gradient(180deg,#fbfdff,var(--bg));
  color:var(--text);
  font:14px/1.5 var(--sans);
}
button,input,select,textarea{font:inherit}
button,input,select{
  min-height:40px;
  border:1px solid var(--line);
  border-radius:10px;
  background:#fff;
  color:var(--text);
  padding:8px 12px;
}
button{
  cursor:pointer;
  transition:background .14s ease,border-color .14s ease,box-shadow .14s ease;
}
button:hover{border-color:#b9c7da;box-shadow:0 8px 18px rgba(37,99,235,.08)}
button:disabled{cursor:not-allowed;opacity:.45;box-shadow:none}
button.primary{background:var(--accent);border-color:var(--accent);color:#fff}
button.secondary{background:#eef5ff;border-color:#cddcff;color:#1f4aa5}
button.danger{background:#fff1f4;border-color:#f3c7d0;color:var(--danger)}
button.warn{background:#fff6e8;border-color:#efdab4;color:var(--warn)}
.app{max-width:1440px;margin:0 auto;padding:18px}
.topbar{
  display:grid;
  grid-template-columns:minmax(0,1fr) auto;
  gap:16px;
  align-items:center;
  padding:16px 18px;
  border:1px solid var(--line);
  background:var(--surface);
  box-shadow:var(--shadow);
  border-radius:14px;
}
h1{margin:0;font-size:26px;line-height:1.1;letter-spacing:0}
.sub{color:var(--muted);margin-top:4px}
.pills,.toolbar,.row,.actions{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.pill{
  display:inline-flex;
  min-height:30px;
  align-items:center;
  border:1px solid var(--line);
  background:var(--surface-2);
  border-radius:999px;
  padding:5px 10px;
  color:#35506f;
  font-size:12px;
}
.layout{
  display:grid;
  grid-template-columns:360px minmax(0,1fr);
  gap:16px;
  margin-top:16px;
}
.panel{
  border:1px solid var(--line);
  background:var(--surface);
  border-radius:14px;
  box-shadow:var(--shadow);
  min-width:0;
}
.panel-head{
  padding:14px 16px;
  border-bottom:1px solid var(--line);
  display:flex;
  justify-content:space-between;
  gap:12px;
  align-items:center;
}
.panel-title{font-size:17px;font-weight:700}
.panel-body{padding:14px 16px}
.path-box,.search-box{width:100%}
.stats{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-top:12px}
.stat{background:var(--surface-2);border:1px solid #e3eaf3;border-radius:10px;padding:10px}
.stat .k{font-size:12px;color:var(--muted)}
.stat .v{font-size:18px;font-weight:700;margin-top:4px}
.file-list{
  margin-top:12px;
  border:1px solid #e0e8f2;
  border-radius:12px;
  overflow:auto;
  height:calc(100dvh - 395px);
  min-height:310px;
  background:#fff;
}
.file-row{
  display:grid;
  grid-template-columns:minmax(0,1fr) auto;
  gap:8px;
  padding:11px 12px;
  border-top:1px solid #eef2f7;
  align-items:center;
}
.file-row:first-child{border-top:0}
.file-row.selected{background:#eef5ff}
.file-main{min-width:0;display:grid;grid-template-columns:38px minmax(0,1fr);gap:10px;align-items:center;cursor:pointer}
.icon{
  width:38px;height:38px;border-radius:9px;
  display:grid;place-items:center;
  border:1px solid #dbe5f1;
  background:#f6f9fd;
  color:#34506d;
  font:700 11px/1 var(--mono);
}
.file-name{font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.file-meta{font-size:12px;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:3px}
.file-actions{display:flex;gap:6px;justify-content:flex-end}
.file-actions button{min-height:32px;padding:6px 8px;font-size:12px;border-radius:8px}
.dropzone{
  margin-top:12px;
  border:1px dashed #adc4e7;
  border-radius:12px;
  background:#f2f7ff;
  padding:15px;
  text-align:center;
}
.dropzone.drag{border-color:var(--accent);box-shadow:0 0 0 2px rgba(37,99,235,.12) inset}
.main-grid{display:grid;grid-template-columns:minmax(0,1fr);gap:16px}
.preview-card,.editor-card{overflow:hidden}
.preview-box{
  min-height:220px;
  border:1px solid #e0e8f2;
  border-radius:12px;
  background:var(--surface-2);
  display:grid;
  place-items:center;
  padding:14px;
  overflow:auto;
}
.preview-box img,.preview-box video{max-width:100%;max-height:320px;border-radius:10px}
.preview-empty{text-align:center;color:var(--muted);max-width:480px}
.code-preview{
  width:100%;
  white-space:pre-wrap;
  word-break:break-word;
  font:13px/1.55 var(--mono);
  color:#253349;
}
.editor-shell{
  border:1px solid var(--code-line);
  border-radius:12px;
  overflow:hidden;
  background:var(--code-bg);
}
.editor-top{
  display:flex;
  justify-content:space-between;
  gap:10px;
  align-items:center;
  padding:10px 12px;
  border-bottom:1px solid var(--code-line);
  color:#aebdda;
  background:#121d2d;
}
.editor-stack{
  position:relative;
  height:calc(100dvh - 430px);
  min-height:360px;
  overflow:hidden;
}
.highlight,.code-input{
  position:absolute;
  inset:0;
  margin:0;
  padding:14px 14px 14px 54px;
  border:0;
  font:13px/20px var(--mono);
  tab-size:2;
  white-space:pre;
  word-break:normal;
  overflow-wrap:normal;
  overflow:auto;
}
.highlight{
  color:var(--code-text);
  pointer-events:none;
}
.highlight code{counter-reset:line}
.highlight .line{display:block;min-height:20px;position:relative}
.highlight .line:before{
  counter-increment:line;
  content:counter(line);
  position:absolute;
  left:-44px;
  width:32px;
  text-align:right;
  color:#5f708e;
}
.code-input{
  resize:none;
  outline:none;
  background:transparent;
  color:transparent;
  caret-color:#ffffff;
  -webkit-text-fill-color:transparent;
}
.tok-key{color:#7dd3fc}
.tok-str{color:#facc15}
.tok-num{color:#a7f3d0}
.tok-com{color:#7890ad}
.tok-api{color:#c4b5fd}
.tok-fn{color:#f0abfc}
.statusbar{
  margin-top:12px;
  min-height:42px;
  border:1px solid #e5dec6;
  border-radius:12px;
  background:#fff8e8;
  color:var(--warn);
  padding:10px 12px;
}
.statusbar.bad{border-color:#f0ccd1;background:#fff1f3;color:var(--danger)}
.queue{display:grid;gap:8px;margin-top:10px}
.queue-item{border:1px solid #e0e8f2;border-radius:10px;padding:9px;background:#fff}
.progress{height:7px;border-radius:999px;background:#e8eef6;overflow:hidden;margin-top:8px}
.progress>div{height:100%;width:0%;background:linear-gradient(90deg,#2563eb,#0f766e)}
.hidden{display:none!important}
@media(max-width:1000px){
  .layout{grid-template-columns:1fr}
  .file-list{height:360px}
  .editor-stack{height:460px}
}
@media(max-width:640px){
  .app{padding:12px}
  .topbar{grid-template-columns:1fr}
  .file-row{grid-template-columns:1fr}
  .file-actions{justify-content:flex-start}
  .stats{grid-template-columns:1fr}
}
</style>
</head>
<body>
<main class="app">
  <section class="topbar">
    <div>
      <h1>Cubic DevTools</h1>
      <div class="sub">文件管理 + DevRun 代码运行器。编辑器只写入 <strong>__RUN_APP_ID__</strong>，不会修改已有 app 源码。</div>
    </div>
    <div class="pills">
      <span class="pill" id="badgeVersion">--</span>
      <span class="pill" id="badgeDir">/sd</span>
      <span class="pill" id="badgeRun">DevRun</span>
    </div>
  </section>

  <section class="layout">
    <aside class="panel">
      <div class="panel-head">
        <div>
          <div class="panel-title">SD 文件</div>
          <div class="sub" id="listHint">准备中</div>
        </div>
        <button id="btnRefresh" type="button">刷新</button>
      </div>
      <div class="panel-body">
        <div class="toolbar">
          <button id="btnUp" type="button">上级</button>
          <button id="btnNewFolder" type="button" class="warn">新目录</button>
          <button id="btnChooseUpload" type="button" class="primary">上传</button>
        </div>
        <div class="row" style="margin-top:10px"><input id="dirPath" class="path-box" value="/sd"></div>
        <div class="row" style="margin-top:8px"><input id="searchInput" class="search-box" placeholder="搜索当前目录"></div>
        <div class="row" style="margin-top:8px">
          <select id="sortSelect">
            <option value="name_asc">名称 A-Z</option>
            <option value="name_desc">名称 Z-A</option>
            <option value="size_desc">体积 大到小</option>
            <option value="size_asc">体积 小到大</option>
            <option value="type">类型</option>
          </select>
          <button id="btnCopyDir" type="button">复制路径</button>
        </div>
        <div class="stats">
          <div class="stat"><div class="k">目录</div><div class="v" id="dirCount">0</div></div>
          <div class="stat"><div class="k">文件</div><div class="v" id="fileCount">0</div></div>
          <div class="stat"><div class="k">总大小</div><div class="v" id="totalBytes">0 B</div></div>
        </div>
        <div class="file-list" id="fileList"></div>
        <div class="dropzone" id="dropzone">
          <strong>拖拽文件到这里上传</strong>
          <div class="sub">上传到当前目录，覆盖同名文件</div>
        </div>
        <div class="queue" id="uploadQueue"></div>
        <input id="fileInput" type="file" multiple class="hidden">
      </div>
    </aside>

    <section class="main-grid">
      <section class="panel preview-card">
        <div class="panel-head">
          <div>
            <div class="panel-title" id="selectedName">未选择项目</div>
            <div class="sub" id="selectedMeta">点击左侧文件进行预览，点击目录进入</div>
          </div>
          <div class="actions">
            <button id="btnPreview" type="button">预览</button>
            <button id="btnDownload" type="button" class="primary">下载</button>
            <button id="btnRename" type="button">重命名</button>
            <button id="btnDelete" type="button" class="danger">删除</button>
          </div>
        </div>
        <div class="panel-body">
          <div class="pills" style="margin-bottom:10px">
            <span class="pill" id="badgeType">--</span>
            <span class="pill" id="badgeMime">--</span>
            <span class="pill" id="badgeSize">--</span>
          </div>
          <div class="preview-box" id="previewBox">
            <div class="preview-empty">选择文件后可预览图片或小文本。二进制大文件请直接下载。</div>
          </div>
          <div class="toolbar" style="margin-top:10px">
            <button id="btnCopyPath" type="button">复制文件路径</button>
            <button id="btnOpenDir" type="button">打开所在目录</button>
          </div>
        </div>
      </section>

      <section class="panel editor-card">
        <div class="panel-head">
          <div>
            <div class="panel-title">DevRun 代码</div>
            <div class="sub" id="runPath">/sd/apps/__RUN_APP_ID__/main.lua</div>
          </div>
          <div class="actions">
            <button id="btnLoadRun" type="button">读取</button>
            <button id="btnSaveRun" type="button" class="secondary">保存</button>
            <button id="btnRun" type="button" class="primary">保存并运行</button>
          </div>
        </div>
        <div class="panel-body">
          <div class="editor-shell">
            <div class="editor-top">
              <span id="codeState">clean</span>
              <span id="codeMeta">1 行 · 0 字符</span>
            </div>
            <div class="editor-stack">
              <pre class="highlight" id="highlight"><code></code></pre>
              <textarea class="code-input" id="codeInput" wrap="off" spellcheck="false" autocorrect="off" autocapitalize="off" autocomplete="off"></textarea>
            </div>
          </div>
          <div class="statusbar" id="statusBox">ready</div>
        </div>
      </section>
    </section>
  </section>
</main>

<script>
const APP_BASE = "__APP_BASE__";
const RUN_APP_ID = "__RUN_APP_ID__";
const textDecoder = new TextDecoder();
let serverInfo = {root_path:"/sd", chunk_size:65536, max_file_size:8388608, preview_text_limit:262144, preview_media_limit:3145728};
let currentDir = "/sd";
let currentItems = [];
let selectedItem = null;
let previewObjectUrl = null;
let loadedCode = "";

function qs(id){return document.getElementById(id)}
function apiUrl(path, params){
  const usp = new URLSearchParams(params || {});
  const str = usp.toString();
  return APP_BASE + path + (str ? "?" + str : "");
}
function fmtBytes(n){
  n = Number(n || 0);
  if(n >= 1048576) return (n / 1048576).toFixed(2) + " MB";
  if(n >= 1024) return (n / 1024).toFixed(1) + " KB";
  return n + " B";
}
function escapeHtml(text){
  return String(text || "").replace(/[&<>"']/g, s => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[s]));
}
function showStatus(text, bad){
  const box = qs("statusBox");
  box.textContent = text || "";
  box.classList.toggle("bad", !!bad);
}
async function parseJson(res){
  const text = await res.text();
  let data;
  try{data = JSON.parse(text)}catch(_){throw new Error(text || res.statusText || "JSON parse failed")}
  if(!res.ok || !data.ok) throw new Error((data && data.error) || res.statusText || "request failed");
  return data;
}
function parentPath(path){
  if(!path || path === serverInfo.root_path) return serverInfo.root_path;
  const parts = path.split("/").filter(Boolean);
  if(parts.length <= 1) return serverInfo.root_path;
  parts.pop();
  return "/" + parts.join("/");
}
function joinPath(dir, name){
  return dir === serverInfo.root_path ? serverInfo.root_path + "/" + name : dir + "/" + name;
}
function fileExt(name){
  const m = String(name || "").toLowerCase().match(/\.([a-z0-9_-]+)$/);
  return m ? m[1] : "";
}
function fileKind(item){return !item ? "unknown" : (item.is_dir ? "dir" : (item.category || "binary"))}
function iconText(item){
  const kind = fileKind(item);
  if(kind === "dir") return "DIR";
  if(kind === "image") return "IMG";
  if(kind === "text") return "TXT";
  if(kind === "audio") return "AUD";
  if(kind === "video") return "VID";
  if(kind === "archive") return "ZIP";
  return (fileExt(item.name) || "BIN").slice(0,3).toUpperCase();
}
function clearPreviewObject(){
  if(previewObjectUrl){
    URL.revokeObjectURL(previewObjectUrl);
    previewObjectUrl = null;
  }
}
function setActionState(){
  const hasItem = !!selectedItem;
  const isDir = hasItem && selectedItem.is_dir;
  qs("btnPreview").disabled = !hasItem || isDir;
  qs("btnDownload").disabled = !hasItem || isDir;
  qs("btnRename").disabled = !hasItem;
  qs("btnDelete").disabled = !hasItem;
  qs("btnCopyPath").disabled = !hasItem;
  qs("btnOpenDir").disabled = !hasItem;
}
function syncSelectedRow(){
  const p = selectedItem && selectedItem.path;
  document.querySelectorAll(".file-row[data-path]").forEach(row => row.classList.toggle("selected", !!p && row.dataset.path === p));
}
function setSelected(item){
  selectedItem = item || null;
  clearPreviewObject();
  if(!item){
    qs("selectedName").textContent = "未选择项目";
    qs("selectedMeta").textContent = "点击左侧文件进行预览，点击目录进入";
    qs("badgeType").textContent = "--";
    qs("badgeMime").textContent = "--";
    qs("badgeSize").textContent = "--";
    qs("previewBox").innerHTML = '<div class="preview-empty">选择文件后可预览图片或小文本。二进制大文件请直接下载。</div>';
    setActionState();
    syncSelectedRow();
    return;
  }
  qs("selectedName").textContent = item.name || item.path;
  qs("selectedMeta").textContent = item.path || "";
  qs("badgeType").textContent = item.is_dir ? "目录" : (item.category || "文件");
  qs("badgeMime").textContent = item.mime || "application/octet-stream";
  qs("badgeSize").textContent = item.is_dir ? "目录" : fmtBytes(item.size || 0);
  qs("previewBox").innerHTML = item.is_dir
    ? '<div class="preview-empty">这是目录。点击左侧目录名称可进入。</div>'
    : '<div class="preview-empty">点击“预览”读取文件内容。</div>';
  setActionState();
  syncSelectedRow();
}
async function fetchFileBytes(path, sizeHint, progressCb){
  let offset = 0;
  const chunks = [];
  while(true){
    const res = await fetch(apiUrl("/api/read", {path, offset, size: serverInfo.chunk_size}));
    if(!res.ok) throw new Error(await res.text() || "读取失败");
    const buf = new Uint8Array(await res.arrayBuffer());
    if(buf.length) chunks.push(buf);
    offset = Number(res.headers.get("x-next-offset") || (offset + buf.length));
    if(progressCb) progressCb(offset, Number(sizeHint || res.headers.get("x-file-size") || 0));
    if(res.headers.get("x-eof") === "1") break;
  }
  const len = chunks.reduce((n,c)=>n+c.length,0);
  const all = new Uint8Array(len);
  let pos = 0;
  for(const part of chunks){all.set(part,pos);pos += part.length}
  return all;
}
function renderList(items){
  currentItems = Array.isArray(items) ? items.slice() : [];
  const keyword = qs("searchInput").value.trim().toLowerCase();
  const mode = qs("sortSelect").value;
  let filtered = currentItems.filter(item => !keyword || String(item.name || "").toLowerCase().includes(keyword));
  filtered.sort((a,b)=>{
    if(mode === "type"){
      if(a.is_dir !== b.is_dir) return a.is_dir ? -1 : 1;
      return ((a.category||"")+a.name).localeCompare((b.category||"")+b.name);
    }
    if(mode === "size_desc"){
      if(a.is_dir !== b.is_dir) return a.is_dir ? -1 : 1;
      return Number(b.size||0)-Number(a.size||0);
    }
    if(mode === "size_asc"){
      if(a.is_dir !== b.is_dir) return a.is_dir ? -1 : 1;
      return Number(a.size||0)-Number(b.size||0);
    }
    const an = String(a.name||"").toLowerCase();
    const bn = String(b.name||"").toLowerCase();
    return mode === "name_desc" ? bn.localeCompare(an) : an.localeCompare(bn);
  });
  const dirs = filtered.filter(i=>i.is_dir).length;
  const files = filtered.length - dirs;
  const bytes = filtered.filter(i=>!i.is_dir).reduce((n,i)=>n+Number(i.size||0),0);
  qs("dirCount").textContent = dirs;
  qs("fileCount").textContent = files;
  qs("totalBytes").textContent = fmtBytes(bytes);
  qs("listHint").textContent = "共 " + filtered.length + " 项";
  qs("badgeDir").textContent = currentDir;
  const box = qs("fileList");
  box.innerHTML = "";
  if(!filtered.length){
    box.innerHTML = '<div class="file-row"><div class="sub">当前目录没有匹配项</div></div>';
    syncSelectedRow();
    return;
  }
  filtered.forEach(item => {
    const row = document.createElement("div");
    row.className = "file-row";
    row.dataset.path = item.path || "";
    const main = document.createElement("div");
    main.className = "file-main";
    main.innerHTML = '<div class="icon">' + escapeHtml(iconText(item)) + '</div><div class="file-info"><div class="file-name" title="' + escapeHtml(item.name || "") + '">' + escapeHtml(item.name || "") + '</div><div class="file-meta" title="' + escapeHtml(item.path || "") + '">' + escapeHtml(item.path || "") + ' · ' + (item.is_dir ? "目录" : fmtBytes(item.size || 0)) + '</div></div>';
    main.onclick = () => item.is_dir ? loadDir(item.path).catch(err=>showStatus(err.message,true)) : setSelected(item);
    const actions = document.createElement("div");
    actions.className = "file-actions";
    const openBtn = document.createElement("button");
    openBtn.textContent = item.is_dir ? "打开" : "预览";
    openBtn.onclick = ev => {ev.stopPropagation(); item.is_dir ? loadDir(item.path).catch(err=>showStatus(err.message,true)) : (setSelected(item), previewSelected().catch(err=>showStatus(err.message,true)))};
    const downBtn = document.createElement("button");
    downBtn.className = "primary";
    downBtn.textContent = item.is_dir ? "路径" : "下载";
    downBtn.onclick = ev => {ev.stopPropagation(); item.is_dir ? copyText(item.path || "") : (setSelected(item), downloadSelected().catch(err=>showStatus(err.message,true)))};
    actions.append(openBtn, downBtn);
    row.append(main, actions);
    box.appendChild(row);
  });
  syncSelectedRow();
}
async function loadInfo(){
  const data = await parseJson(await fetch(apiUrl("/api/info")));
  serverInfo = data;
  qs("badgeVersion").textContent = data.version || "--";
  qs("badgeRun").textContent = data.run_app_id || RUN_APP_ID;
  qs("runPath").textContent = data.run_app_main || "/sd/apps/" + RUN_APP_ID + "/main.lua";
}
async function loadDir(path){
  const target = path || currentDir || serverInfo.root_path;
  const data = await parseJson(await fetch(apiUrl("/api/list", {path: target})));
  currentDir = data.path || serverInfo.root_path;
  localStorage.setItem("devtools:lastDir", currentDir);
  qs("dirPath").value = currentDir;
  setSelected(null);
  renderList(data.items || []);
  showStatus("已载入 " + currentDir, false);
}
async function previewSelected(){
  if(!selectedItem) throw new Error("请先选择文件");
  if(selectedItem.is_dir) throw new Error("目录无需预览");
  const kind = fileKind(selectedItem);
  const size = Number(selectedItem.size || 0);
  clearPreviewObject();
  qs("previewBox").innerHTML = '<div class="preview-empty">正在读取文件...</div>';
  if(kind === "image"){
    if(size > serverInfo.preview_media_limit){
      qs("previewBox").innerHTML = '<div class="preview-empty">图片过大，请直接下载查看。</div>';
      return;
    }
    const bytes = await fetchFileBytes(selectedItem.path, size, (done,total)=>showStatus("预览读取 " + fmtBytes(done) + " / " + fmtBytes(total || size), false));
    previewObjectUrl = URL.createObjectURL(new Blob([bytes], {type:selectedItem.mime || "application/octet-stream"}));
    qs("previewBox").innerHTML = '<img alt="preview">';
    qs("previewBox").querySelector("img").src = previewObjectUrl;
    showStatus("预览已就绪: " + selectedItem.name, false);
    return;
  }
  if(kind === "text"){
    if(size > serverInfo.preview_text_limit){
      qs("previewBox").innerHTML = '<div class="preview-empty">文本文件过大，请直接下载查看。</div>';
      return;
    }
    const bytes = await fetchFileBytes(selectedItem.path, size, (done,total)=>showStatus("文本读取 " + fmtBytes(done) + " / " + fmtBytes(total || size), false));
    qs("previewBox").innerHTML = '<div class="code-preview">' + escapeHtml(textDecoder.decode(bytes)) + '</div>';
    showStatus("文本预览已就绪: " + selectedItem.name, false);
    return;
  }
  qs("previewBox").innerHTML = '<div class="preview-empty">该类型不提供网页内预览，请直接下载。</div>';
}
async function downloadSelected(){
  if(!selectedItem) throw new Error("请先选择文件");
  if(selectedItem.is_dir) throw new Error("目录不能直接下载");
  const bytes = await fetchFileBytes(selectedItem.path, selectedItem.size || 0, (done,total)=>showStatus("下载读取 " + fmtBytes(done) + " / " + fmtBytes(total || 0), false));
  const url = URL.createObjectURL(new Blob([bytes], {type:selectedItem.mime || "application/octet-stream"}));
  const a = document.createElement("a");
  a.href = url;
  a.download = selectedItem.name || "download.bin";
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
  showStatus("已下载 " + (selectedItem.name || ""), false);
}
async function renamePath(item){
  const nextName = (prompt("输入新名称", item.name || "") || "").trim();
  if(!nextName || nextName === item.name) return;
  const newPath = joinPath(parentPath(item.path), nextName);
  await parseJson(await fetch(apiUrl("/api/rename", {path:item.path, new_path:newPath}), {method:"POST"}));
  if(selectedItem && selectedItem.path === item.path) setSelected(null);
  await loadDir(currentDir);
  showStatus("已重命名为 " + nextName, false);
}
async function deletePath(item){
  const api = item.is_dir ? "/api/rmdir" : "/api/remove";
  const params = item.is_dir ? {path:item.path, recursive:1} : {path:item.path};
  if(!confirm((item.is_dir ? "确认递归删除目录及其全部内容？" : "确认删除文件？") + "\n" + item.path)) return;
  await parseJson(await fetch(apiUrl(api, params), {method:"DELETE"}));
  if(selectedItem && selectedItem.path === item.path) setSelected(null);
  await loadDir(currentDir);
  showStatus("已删除 " + item.name, false);
}
async function createFolder(){
  const name = (prompt("输入新目录名", "") || "").trim();
  if(!name) return;
  await parseJson(await fetch(apiUrl("/api/mkdir", {path:joinPath(currentDir, name)}), {method:"POST"}));
  await loadDir(currentDir);
  showStatus("已创建目录 " + name, false);
}
function addQueueItem(name){
  const wrap = document.createElement("div");
  wrap.className = "queue-item";
  wrap.innerHTML = '<strong style="word-break:break-all">' + escapeHtml(name) + '</strong><span class="sub" data-status style="float:right">等待</span><div class="progress"><div></div></div>';
  qs("uploadQueue").prepend(wrap);
  return {bar:wrap.querySelector(".progress>div"), status:wrap.querySelector("[data-status]")};
}
async function uploadOneFile(file){
  if(file.size > serverInfo.max_file_size) throw new Error(file.name + " 超过单文件大小限制");
  const item = addQueueItem(file.name);
  let offset = 0;
  while(offset < file.size || (file.size === 0 && offset === 0)){
    const end = Math.min(offset + serverInfo.chunk_size, file.size);
    const res = await fetch(apiUrl("/api/upload", {path:joinPath(currentDir, file.name), offset, total:file.size}), {method:"PUT", body:file.slice(offset, end)});
    const data = await parseJson(res);
    offset = Number(data.next_offset || end);
    const pct = file.size > 0 ? Math.min(100, Math.round(offset * 100 / file.size)) : 100;
    item.bar.style.width = pct + "%";
    item.status.textContent = pct + "%";
    if(file.size === 0) break;
  }
}
async function uploadFiles(files){
  const arr = Array.from(files || []);
  if(!arr.length) return;
  for(const f of arr){
    try{showStatus("上传 " + f.name, false); await uploadOneFile(f)}
    catch(err){showStatus(err.message, true)}
  }
  await loadDir(currentDir);
  showStatus("上传任务结束", false);
}
function copyText(text){
  if(!text) return;
  if(!navigator.clipboard){showStatus("浏览器不支持自动复制", true); return}
  navigator.clipboard.writeText(text).then(()=>showStatus("已复制: " + text, false)).catch(()=>showStatus("复制失败", true));
}
function highlightLua(text){
  const keywords = /^(and|break|do|else|elseif|end|false|for|function|goto|if|in|local|nil|not|or|repeat|return|then|true|until|while)\b/;
  const apis = /^(app|file|httpd|http|json|sjson|tmr|lv_[A-Za-z0-9_]+|LV_[A-Za-z0-9_]+|sys|time|math|string|table)\b/;
  const out = [];
  const lines = String(text || "").split("\n");
  for(const line of lines){
    let i = 0, html = "";
    while(i < line.length){
      const rest = line.slice(i);
      let m;
      if(rest.startsWith("--")){html += '<span class="tok-com">' + escapeHtml(rest) + '</span>'; break}
      if((m = rest.match(/^"([^"\\]|\\.)*"/)) || (m = rest.match(/^'([^'\\]|\\.)*'/))){
        html += '<span class="tok-str">' + escapeHtml(m[0]) + '</span>'; i += m[0].length; continue;
      }
      if((m = rest.match(/^\d+(\.\d+)?/))){
        html += '<span class="tok-num">' + escapeHtml(m[0]) + '</span>'; i += m[0].length; continue;
      }
      if((m = rest.match(keywords))){
        html += '<span class="tok-key">' + escapeHtml(m[0]) + '</span>'; i += m[0].length; continue;
      }
      if((m = rest.match(apis))){
        html += '<span class="tok-api">' + escapeHtml(m[0]) + '</span>'; i += m[0].length; continue;
      }
      if((m = rest.match(/^[A-Za-z_][A-Za-z0-9_]*(?=\s*\()/))){
        html += '<span class="tok-fn">' + escapeHtml(m[0]) + '</span>'; i += m[0].length; continue;
      }
      html += escapeHtml(line[i]);
      i += 1;
    }
    out.push('<span class="line">' + (html || " ") + '</span>');
  }
  return out.join("");
}
function syncHighlight(){
  const input = qs("codeInput");
  qs("highlight").querySelector("code").innerHTML = highlightLua(input.value);
  qs("highlight").scrollTop = input.scrollTop;
  qs("highlight").scrollLeft = input.scrollLeft;
  const lines = input.value ? input.value.split("\n").length : 1;
  qs("codeMeta").textContent = lines + " 行 · " + input.value.length + " 字符";
  qs("codeState").textContent = input.value === loadedCode ? "clean" : "modified";
}
async function loadRunCode(){
  const res = await fetch(apiUrl("/api/code/read"), {cache:"no-store"});
  const text = await res.text();
  if(!res.ok) throw new Error(text || "读取 DevRun 失败");
  loadedCode = text;
  qs("codeInput").value = text;
  syncHighlight();
  showStatus("DevRun 源码已读取", false);
}
async function saveRunCode(run){
  const res = await fetch(apiUrl(run ? "/api/code/run" : "/api/code/save"), {
    method:"POST",
    headers:{"content-type":"text/plain; charset=utf-8"},
    body:qs("codeInput").value || ""
  });
  const data = await parseJson(res);
  loadedCode = qs("codeInput").value || "";
  syncHighlight();
  showStatus(run ? "已保存并启动 DevRun" : "已保存 DevRun", false);
  return data;
}
qs("btnRefresh").onclick = () => loadDir(qs("dirPath").value.trim() || serverInfo.root_path).catch(err=>showStatus(err.message,true));
qs("btnUp").onclick = () => loadDir(parentPath(currentDir)).catch(err=>showStatus(err.message,true));
qs("btnNewFolder").onclick = () => createFolder().catch(err=>showStatus(err.message,true));
qs("btnChooseUpload").onclick = () => qs("fileInput").click();
qs("fileInput").onchange = () => {uploadFiles(qs("fileInput").files).catch(err=>showStatus(err.message,true)); qs("fileInput").value = ""};
qs("searchInput").oninput = () => renderList(currentItems);
qs("sortSelect").onchange = () => renderList(currentItems);
qs("dirPath").onkeydown = ev => {if(ev.key === "Enter") loadDir(qs("dirPath").value.trim() || serverInfo.root_path).catch(err=>showStatus(err.message,true))};
qs("btnCopyDir").onclick = () => copyText(currentDir);
qs("btnPreview").onclick = () => previewSelected().catch(err=>showStatus(err.message,true));
qs("btnDownload").onclick = () => downloadSelected().catch(err=>showStatus(err.message,true));
qs("btnRename").onclick = () => selectedItem ? renamePath(selectedItem).catch(err=>showStatus(err.message,true)) : showStatus("请先选择项目", true);
qs("btnDelete").onclick = () => selectedItem ? deletePath(selectedItem).catch(err=>showStatus(err.message,true)) : showStatus("请先选择项目", true);
qs("btnCopyPath").onclick = () => selectedItem ? copyText(selectedItem.path || "") : showStatus("请先选择项目", true);
qs("btnOpenDir").onclick = () => selectedItem ? loadDir(selectedItem.is_dir ? selectedItem.path : parentPath(selectedItem.path)).catch(err=>showStatus(err.message,true)) : showStatus("请先选择项目", true);
qs("btnLoadRun").onclick = () => loadRunCode().catch(err=>showStatus(err.message,true));
qs("btnSaveRun").onclick = () => saveRunCode(false).catch(err=>showStatus(err.message,true));
qs("btnRun").onclick = () => saveRunCode(true).catch(err=>showStatus(err.message,true));
qs("codeInput").addEventListener("input", syncHighlight);
qs("codeInput").addEventListener("scroll", syncHighlight);
qs("codeInput").addEventListener("keydown", ev => {
  if(ev.key === "Tab"){
    ev.preventDefault();
    const el = ev.currentTarget;
    const s = el.selectionStart, e = el.selectionEnd;
    el.value = el.value.slice(0, s) + "  " + el.value.slice(e);
    el.selectionStart = el.selectionEnd = s + 2;
    syncHighlight();
  }
});
const dropzone = qs("dropzone");
["dragenter","dragover"].forEach(name => dropzone.addEventListener(name, ev => {ev.preventDefault(); dropzone.classList.add("drag")}));
["dragleave","drop"].forEach(name => dropzone.addEventListener(name, ev => {ev.preventDefault(); dropzone.classList.remove("drag")}));
dropzone.addEventListener("drop", ev => uploadFiles(ev.dataTransfer && ev.dataTransfer.files).catch(err=>showStatus(err.message,true)));
(async function boot(){
  try{
    setActionState();
    syncHighlight();
    await loadInfo();
    await loadDir(localStorage.getItem("devtools:lastDir") || serverInfo.root_path);
    await loadRunCode();
    showStatus("服务已连接", false);
  }catch(err){
    showStatus(err.message || String(err), true);
  }
})();
</script>
</body>
</html>
]==]

function APP.register_route(method, route, handler)
  local err = httpd.dynamic(method, route, handler)
  if err then
    error("httpd.dynamic failed: " .. text_or(route, "") .. " (" .. tostring(err) .. ")")
  end
  APP.routes[#APP.routes + 1] = { method = method, route = route }
end

function APP.try_register_route(method, route, handler)
  local err = httpd.dynamic(method, route, handler)
  if err then
    print("[devtools] optional route skipped", text_or(route, ""), tostring(err))
    return false
  end
  APP.routes[#APP.routes + 1] = { method = method, route = route }
  return true
end

function APP.unregister_all_routes()
  for i = #APP.routes, 1, -1 do
    local item = APP.routes[i]
    pcall(function()
      httpd.unregister(item.method, item.route)
    end)
  end
  APP.routes = {}
end

function APP.stop(reason)
  if APP.shutting_down then
    return
  end
  APP.shutting_down = true
  APP.unregister_all_routes()
  print("[devtools] stop", text_or(reason, ""))
end

ensure_run_app()
httpd.start({
  webroot = "/sd",
  auto_index = httpd.INDEX_NONE,
  max_handlers = 36
})

APP.register_route(httpd.GET, APP.ROUTE_BASE, APP.route_redirect)
APP.register_route(httpd.GET, APP.ROUTE_BASE .. "/", APP.route_index)
APP.register_route(httpd.GET, APP.ROUTE_BASE .. "/favicon.ico", APP.route_favicon)
if APP.LEGACY_ROUTE_BASE ~= APP.ROUTE_BASE then
  APP.try_register_route(httpd.GET, APP.LEGACY_ROUTE_BASE, APP.route_redirect)
  APP.try_register_route(httpd.GET, APP.LEGACY_ROUTE_BASE .. "/", APP.route_redirect)
end
APP.try_register_route(httpd.GET, "/codeeditor", APP.route_redirect)
APP.try_register_route(httpd.GET, "/codeeditor/", APP.route_redirect)

APP.register_route(httpd.GET, APP.API_PREFIX .. "/info", APP.api_info)
APP.register_route(httpd.GET, APP.API_PREFIX .. "/list", APP.api_list)
APP.register_route(httpd.GET, APP.API_PREFIX .. "/stat", APP.api_stat)
APP.register_route(httpd.GET, APP.API_PREFIX .. "/read", APP.api_read)
APP.register_route(httpd.GET, APP.API_PREFIX .. "/apps", APP.api_apps)
APP.register_route(httpd.GET, APP.API_PREFIX .. "/code/read", APP.api_read_run_code)

APP.register_route(httpd.POST, APP.API_PREFIX .. "/mkdir", APP.api_mkdir)
APP.register_route(httpd.POST, APP.API_PREFIX .. "/rename", APP.api_rename)
APP.register_route(httpd.POST, APP.API_PREFIX .. "/code/save", APP.route_save_code)
APP.register_route(httpd.POST, APP.API_PREFIX .. "/code/run", APP.route_run_code)

APP.register_route(httpd.PUT, APP.API_PREFIX .. "/upload", APP.api_upload)

APP.register_route(httpd.DELETE, APP.API_PREFIX .. "/remove", APP.api_remove)
APP.register_route(httpd.DELETE, APP.API_PREFIX .. "/rmdir", APP.api_rmdir)

set_status("HTTP ready")
mark_action("ready", APP.ROUTE_BASE)
update_screen()
print("[devtools] ready", APP.VERSION, APP.ROUTE_BASE)
