local CURRENT_APP = app and app.current and app.current()
local APP_DIR = (CURRENT_APP and CURRENT_APP.entry and CURRENT_APP.entry:gsub("\\", "/"):match("^(.*)/[^/]+$")) or "/sd/apps/ebook"
local APP_ID = (CURRENT_APP and CURRENT_APP.id) or "ebook"
local BOOKS_DIR = "/sd/ebooks"
local INDEX_DIR = BOOKS_DIR .. "/.index"
local STATE_PATH = BOOKS_DIR .. "/.reader_state.json"
local SETTINGS_PATH = "/sd/apps/settings.json"

if _G.__ebook_reader and _G.__ebook_reader.stop then
  pcall(_G.__ebook_reader.stop, _G.__ebook_reader, "reload")
end

local MAIN = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local ALIGN_LEFT = rawget(_G, "LV_TEXT_ALIGN_LEFT") or 0
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local FONT_FALLBACK = rawget(_G, "lv_font_montserrat_16") or rawget(_G, "LV_FONT_MONTSERRAT_16")
local FONT_SMALL = rawget(_G, "lv_font_montserrat_12") or rawget(_G, "LV_FONT_MONTSERRAT_12")
local FONT_BODY_FALLBACK = rawget(_G, "lv_font_montserrat_18") or rawget(_G, "LV_FONT_MONTSERRAT_18") or FONT_FALLBACK
local JSON = rawget(_G, "json") or rawget(_G, "sjson")
local PAGE_CELLS = 32
local PAGE_LINES = 9
local PAGE_READ_BYTES = 4096
local INDEX_CHUNK_BYTES = 4096
local MAX_CHAPTERS = 4096
local INDEX_MAGIC = "EBI3"

local function now_ms()
  if type(millis) == "function" then
    local ok, value = pcall(millis)
    if ok and type(value) == "number" then return value end
  end
  return math.floor(os.clock() * 1000)
end

local function close_fd(fd)
  if not fd then return end
  pcall(function() fd:close() end)
end

local function ensure_dir(path)
  if file and file.mkdir then pcall(file.mkdir, path) end
end

local function read_small(path, limit)
  if not file or not file.open then return nil end
  local fd = file.open(path, "r")
  if not fd then return nil end
  local ok, raw = pcall(function() return fd:read(limit or 262144) end)
  close_fd(fd)
  if ok and type(raw) == "string" then return raw end
  return nil
end

local function write_text(path, raw)
  if file and file.putcontents then
    local ok, result = pcall(file.putcontents, path, raw)
    if ok and result ~= false then return true end
  end
  if not file or not file.open then return false end
  local fd = file.open(path, "w+")
  if not fd then return false end
  local ok = pcall(function() fd:write(raw) fd:flush() end)
  close_fd(fd)
  return ok
end

local function pack_u16(value)
  value = math.floor(tonumber(value) or 0) % 65536
  return string.char(value % 256, math.floor(value / 256) % 256)
end

local function unsigned_u32(value)
  value = math.floor(tonumber(value) or 0)
  if value < 0 then value = value + 4294967296 end
  return value % 4294967296
end

local function signed_i32(value)
  value = unsigned_u32(value)
  if value >= 2147483648 then value = value - 4294967296 end
  if math.tointeger then return math.tointeger(value) or value end
  return value
end

local function pack_u32(value)
  value = unsigned_u32(value)
  return string.char(value % 256, math.floor(value / 256) % 256, math.floor(value / 65536) % 256, math.floor(value / 16777216) % 256)
end

local function unpack_u16(raw, pos)
  if not raw or pos + 1 > #raw then return nil, pos end
  return raw:byte(pos) + raw:byte(pos + 1) * 256, pos + 2
end

local function unpack_u32(raw, pos)
  if not raw or pos + 3 > #raw then return nil, pos end
  local value = raw:byte(pos) + raw:byte(pos + 1) * 256 + raw:byte(pos + 2) * 65536 + raw:byte(pos + 3) * 16777216
  return unsigned_u32(value), pos + 4
end

local CRC32_TABLE = {}
for i = 0, 255 do
  local value = i
  for _ = 1, 8 do value = ((value & 1) ~= 0) and ((value >> 1) ~ 0xEDB88320) or (value >> 1) end
  CRC32_TABLE[i] = value & 0xFFFFFFFF
end

local function crc32_update(crc, raw)
  crc = tonumber(crc) or 0xFFFFFFFF
  for i = 1, #(raw or "") do crc = CRC32_TABLE[(crc ~ raw:byte(i)) & 0xFF] ~ (crc >> 8) end
  return crc & 0xFFFFFFFF
end

local function book_fingerprint(book)
  local fd = file and file.open and file.open(book.path, "r")
  if not fd then return nil end
  local crc, blocks, block_size = 0xFFFFFFFF, 16, 512
  local ok = pcall(function()
    for i = 0, blocks - 1 do
      local offset = book.size <= block_size and 0 or math.floor((book.size - block_size) * i / (blocks - 1))
      fd:seek("set", offset)
      crc = crc32_update(crc, fd:read(math.min(block_size, book.size - offset)) or "")
    end
  end)
  close_fd(fd)
  if not ok then return nil end
  return unsigned_u32((~crc) & 0xFFFFFFFF)
end

local function json_decode(raw)
  if not raw or not JSON or not JSON.decode then return nil end
  local ok, value = pcall(JSON.decode, raw)
  return ok and type(value) == "table" and value or nil
end

local function json_encode(value)
  if not JSON or not JSON.encode then return nil end
  local ok, raw = pcall(JSON.encode, value)
  return ok and type(raw) == "string" and raw or nil
end

local function normalize_language(value)
  local text = tostring(value or ""):gsub("_", "-")
  if text == "en" or text:match("^en%-") then return "en" end
  if text == "ja" or text:match("^ja%-") then return "ja" end
  if text == "zh-TW" or text == "zh-Hant" or text:match("^zh%-Hant") or text:match("^zh%-HK") then return "zh-TW" end
  return "zh-CN"
end

local RUNTIME_SETTINGS = json_decode(read_small(SETTINGS_PATH, 65536)) or {}
local LANGUAGE = normalize_language(RUNTIME_SETTINGS.language or RUNTIME_SETTINGS.locale or RUNTIME_SETTINGS.lang)
local TEXT = {
  ["zh-CN"] = {
    app_title="电子书", empty="书库为空\n\n请打开网页控制页上传电子书。\n支持 EPUB / UTF-8 TXT / Markdown。", choose="请选择一本电子书", waiting="等待书籍", page_hint="‹  翻页  ›",
    toc="章节目录", library="书库", items="%d 项", menu_hint="方向键选择  A确认  B返回  START切换", start="开始阅读", chapter="章节 %d",
    index_loaded="本地目录已载入", index_done="目录已保存 · %d 章", index_failed="目录读取失败", index_build="正在生成目录 %d%% · %d 章", index_start="正在生成目录 0%", index_resume="继续生成目录 %d%% · %d 章", index_footer="目录 %d%% · %s",
    open_failed="无法打开电子书", read_failed="读取失败", end_book="—— 全书完 ——", no_choice="没有可选择的项目", no_book="没有打开电子书", finished="已经读完", first="已经是第一页",
    chapter_missing="章节不存在", invalid_book="电子书路径无效", missing_book="电子书不存在或为空", book_missing="书籍不存在", invalid_path="路径无效", delete_failed="删除失败", web_failed="Web 控制页加载失败", unknown_action="未知操作", encoding_bad="文件不是 UTF-8 或已经被错误转码\n\n请在新版网页控制页重新上传原始文件。", main_body="正文", epub_loaded="EPUB 目录已载入 · %d 章", epub_invalid="EPUB 缓存不完整",
  },
  en = {
    app_title="E-Book", empty="Library is empty\n\nUpload a book from the Web UI.\nEPUB / UTF-8 TXT / Markdown supported.", choose="Choose a book", waiting="Waiting for a book", page_hint="‹  PAGE  ›",
    toc="CONTENTS", library="LIBRARY", items="%d items", menu_hint="D-pad select  A enter  B back  START switch", start="Start reading", chapter="Chapter %d",
    index_loaded="Local contents loaded", index_done="Contents saved · %d chapters", index_failed="Contents scan failed", index_build="Building contents %d%% · %d chapters", index_start="Building contents 0%", index_resume="Resuming contents %d%% · %d chapters", index_footer="INDEX %d%% · %s",
    open_failed="Unable to open book", read_failed="Read failed", end_book="—— END ——", no_choice="Nothing to select", no_book="No book is open", finished="End of book", first="First page",
    chapter_missing="Chapter not found", invalid_book="Invalid book path", missing_book="Book is missing or empty", book_missing="Book not found", invalid_path="Invalid path", delete_failed="Delete failed", web_failed="Web UI failed to load", unknown_action="Unknown action", encoding_bad="This file is not UTF-8 or was converted incorrectly.\n\nUpload the original again from the updated Web UI.", main_body="Text", epub_loaded="EPUB contents loaded · %d chapters", epub_invalid="EPUB cache is incomplete",
  },
  ja = {
    app_title="電子書", empty="ライブラリは空です\n\nWeb画面から本をアップロードしてください。\nEPUB / UTF-8 TXT / Markdown 対応。", choose="本を選択", waiting="本を待っています", page_hint="‹  ページ  ›",
    toc="目次", library="ライブラリ", items="%d 件", menu_hint="方向キー選択  A決定  B戻る  START切替", start="読み始める", chapter="第 %d 章",
    index_loaded="保存済み目次を読み込みました", index_done="目次を保存しました · %d 章", index_failed="目次の読み込みに失敗", index_build="目次を作成中 %d%% · %d 章", index_start="目次を作成中 0%", index_resume="目次を再開中 %d%% · %d 章", index_footer="目次 %d%% · %s",
    open_failed="電子書を開けません", read_failed="読み込み失敗", end_book="—— 読了 ——", no_choice="選択項目がありません", no_book="本が開かれていません", finished="最後のページです", first="最初のページです",
    chapter_missing="章がありません", invalid_book="本のパスが無効です", missing_book="本がないか空です", book_missing="本が見つかりません", invalid_path="パスが無効です", delete_failed="削除失敗", web_failed="Web画面を読み込めません", unknown_action="不明な操作", encoding_bad="UTF-8 ではないか、誤って変換されたファイルです。\n\n更新後のWeb画面から元ファイルを再送信してください。", main_body="本文", epub_loaded="EPUB 目次を読み込みました · %d 章", epub_invalid="EPUB キャッシュが不完全です",
  },
  ["zh-TW"] = {
    app_title="電子書", empty="書庫為空\n\n請從網頁控制頁上傳電子書。\n支援 EPUB / UTF-8 TXT / Markdown。", choose="請選擇一本電子書", waiting="等待書籍", page_hint="‹  翻頁  ›",
    toc="章節目錄", library="書庫", items="%d 項", menu_hint="方向鍵選擇  A確認  B返回  START切換", start="開始閱讀", chapter="章節 %d",
    index_loaded="本機目錄已載入", index_done="目錄已儲存 · %d 章", index_failed="目錄讀取失敗", index_build="正在產生目錄 %d%% · %d 章", index_start="正在產生目錄 0%", index_resume="繼續產生目錄 %d%% · %d 章", index_footer="目錄 %d%% · %s",
    open_failed="無法開啟電子書", read_failed="讀取失敗", end_book="—— 全書完 ——", no_choice="沒有可選擇的項目", no_book="沒有開啟電子書", finished="已經讀完", first="已經是第一頁",
    chapter_missing="章節不存在", invalid_book="電子書路徑無效", missing_book="電子書不存在或為空", book_missing="書籍不存在", invalid_path="路徑無效", delete_failed="刪除失敗", web_failed="Web 控制頁載入失敗", unknown_action="未知操作", encoding_bad="檔案不是 UTF-8 或已被錯誤轉碼\n\n請從新版網頁控制頁重新上傳原始檔案。", main_body="正文", epub_loaded="EPUB 目錄已載入 · %d 章", epub_invalid="EPUB 快取不完整",
  },
}
local function T(key, ...)
  local value = (TEXT[LANGUAGE] and TEXT[LANGUAGE][key]) or TEXT.en[key] or key
  if select("#", ...) > 0 then return string.format(value, ...) end
  return value
end

local function normalize_text_color(value)
  local hex = tostring(value or ""):match("^#?(%x%x%x%x%x%x)$")
  return hex and tonumber(hex, 16) or 0xE9E4D8
end

local function trim(text)
  return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function utf8_clip(text, max_chars)
  text = tostring(text or "")
  local pos, count = 1, 0
  while pos <= #text and count < max_chars do
    local b = text:byte(pos)
    local n = (b and b < 0x80) and 1 or (b and b < 0xE0) and 2 or (b and b < 0xF0) and 3 or 4
    if pos + n - 1 > #text then break end
    pos = pos + n
    count = count + 1
  end
  if pos <= #text then return text:sub(1, pos - 1) .. "…" end
  return text
end

local function safe_book_path(path)
  path = tostring(path or ""):gsub("\\", "/")
  if path:sub(1, #BOOKS_DIR + 1) ~= BOOKS_DIR .. "/" then return nil end
  if path:find("..", 1, true) then return nil end
  local lower = path:lower()
  if not lower:match("%.txt$") and not lower:match("%.md$") and not lower:match("%.epubbook$") then return nil end
  return path
end

local function safe_epub_cache_path(path)
  path = tostring(path or ""):gsub("\\", "/")
  if path:sub(1, #BOOKS_DIR + 7) ~= BOOKS_DIR .. "/.epub/" then return nil end
  if path:find("..", 1, true) then return nil end
  return path
end

local function file_size(path, entry)
  local n = entry and tonumber(entry.size or entry.file_size)
  if n and n >= 0 then return n end
  if file and file.stat then
    local ok, st = pcall(file.stat, path)
    if ok and type(st) == "table" then
      n = tonumber(st.size or st.file_size)
      if n then return n end
    end
  end
  local fd = file and file.open and file.open(path, "r")
  if not fd then return 0 end
  local ok, size = pcall(function() return fd:seek("end", 0) end)
  close_fd(fd)
  return ok and tonumber(size) or 0
end

local function path_name(path)
  return tostring(path or ""):match("([^/]+)$") or "book"
end

local function display_name(path)
  return path_name(path):gsub("%.[^%.]+$", "")
end

local function load_epub_book(path)
  local doc = json_decode(read_small(path, 524288))
  if type(doc) ~= "table" or doc.format ~= "epub" or type(doc.sections) ~= "table" or #doc.sections == 0 then return nil end
  local images = {}
  if type(doc.images) == "table" then
    for i = 1, math.min(#doc.images, 4096) do
      local item = doc.images[i]
      local image_path = type(item) == "table" and safe_epub_cache_path(item.path)
      if image_path then
        images[i] = {
          index = i,
          path = image_path,
          width = math.max(1, math.min(296, math.floor(tonumber(item.width) or 1))),
          height = math.max(1, math.min(174, math.floor(tonumber(item.height) or 1))),
          alt = utf8_clip(trim(item.alt), 40),
        }
      end
    end
  end
  local sections, total = {}, 0
  for i = 1, math.min(#doc.sections, MAX_CHAPTERS) do
    local item = doc.sections[i]
    local section_path = type(item) == "table" and safe_epub_cache_path(item.path)
    local size = section_path and math.max(0, math.floor(tonumber(item.size) or file_size(section_path))) or 0
    if section_path and size > 0 then
      sections[#sections + 1] = {
        index = #sections + 1,
        path = section_path,
        size = size,
        offset = total,
        title = utf8_clip(trim(item.title or T("chapter", #sections + 1)), 42),
      }
      total = total + size
    end
  end
  if #sections == 0 or total <= 0 then return nil end
  return {
    format = "epub",
    path = path,
    file_name = path_name(path),
    name = trim(doc.title) ~= "" and trim(doc.title) or display_name(path),
    author = trim(doc.author),
    size = total,
    cache_dir = safe_epub_cache_path(doc.cache_dir),
    sections = sections,
    images = images,
  }
end

local function index_path(book)
  local name = path_name(book.path):gsub("[^%w%._%-]", "_"):sub(1, 54)
  -- Keep the hash below 2^31. This firmware builds Lua with a numeric type
  -- where large FNV multiplication cannot always be represented as integer.
  local hash = 5381
  for i = 1, #book.path do hash = math.floor((hash * 131 + book.path:byte(i)) % 2147483647) end
  return string.format("%s/%s_%08x.idx", INDEX_DIR, name, hash)
end

local function partial_index_path(book)
  return index_path(book) .. ".part"
end

local function chapter_title(line)
  local s = trim(tostring(line or ""):gsub("\r", ""):gsub("　", " "))
  if s:sub(1, 3) == string.char(239, 187, 191) then s = s:sub(4) end
  if s == "" or #s > 360 then return nil end
  local hashes, md = s:match("^(#+)%s+(.+)$")
  if hashes and #hashes <= 6 and md and #trim(md) > 0 and #md <= 180 then return utf8_clip(trim(md), 42) end
  local short_heading = #s <= 180 and not s:find("。", 1, true) and not s:find("！", 1, true) and not s:find("？", 1, true) and not s:find("；", 1, true)
  if short_heading and s:match("^第[0-9零一二三四五六七八九十百千万两〇]+[章节卷回部篇集]") then return utf8_clip(s, 42) end
  if short_heading and s:match("^[卷部篇][0-9零一二三四五六七八九十百千万两〇]+") then return utf8_clip(s, 42) end
  local lower = s:lower()
  if short_heading and (lower:match("^chapter%s+[%divxlcdm%-%.]+") or lower:match("^part%s+[%divxlcdm%-%.]+")) then return utf8_clip(s, 42) end
  local exact_heads = { "序章", "序言", "前言", "楔子", "引子", "尾声", "后记", "终章", "番外" }
  for _, head in ipairs(exact_heads) do if short_heading and s:sub(1, #head) == head then return utf8_clip(s, 42) end end
  return nil
end

local APP = {
  version = "0.4.0",
  language = LANGUAGE,
  running = true,
  books = {},
  current = nil,
  chapters = {},
  offset = 0,
  next_offset = nil,
  page_text = "",
  page_image = nil,
  history = {},
  indexer = nil,
  index_progress = 0,
  index_status = "idle",
  index_message = "",
  ui = {},
  timers = {},
  font_handle = nil,
  body_font_handle = nil,
  font = FONT_FALLBACK,
  body_font = FONT_BODY_FALLBACK,
  font_size = 18,
  text_color = 0xE9E4D8,
  saved = {},
  menu = { open = false, kind = "toc", selected = 1, first = 1 },
  controller_buttons = 0,
  controller_timer = nil,
  repeat_left = 0,
  repeat_right = 0,
}
_G.__ebook_reader = APP

function APP:translate(key, ...)
  return T(key, ...)
end

function APP:load_font()
  if not lv_font_load then return end
  local file_name = LANGUAGE == "ja" and "launcher_ui_ja_16.bin" or LANGUAGE == "zh-TW" and "launcher_ui_zh_tw_16.bin" or "launcher_ui_zh_cn_16.bin"
  local candidates = {
    APP_DIR .. "/font/" .. file_name,
    "/sd/apps/launcher/font/" .. file_name,
    APP_DIR .. "/font/launcher_ui_zh_cn_16.bin",
    APP_DIR .. "/font/18chinese.bin",
  }
  for _, path in ipairs(candidates) do
    local ok, handle = pcall(lv_font_load, path)
    if ok and tonumber(handle) and tonumber(handle) > 0 then
      self.font_handle = handle
      self.font = handle
      break
    end
  end
  if LANGUAGE == "zh-CN" or LANGUAGE == "en" then
    local body_candidates = {
      APP_DIR .. "/font/18chinese.bin",
      "/sd/apps/time-calendar-weather-memo/font/18chinese.bin",
    }
    for _, path in ipairs(body_candidates) do
      local ok, handle = pcall(lv_font_load, path)
      if ok and tonumber(handle) and tonumber(handle) > 0 then
        self.body_font_handle = handle
        self.body_font = handle
        break
      end
    end
  else
    self.body_font = self.font
    PAGE_CELLS, PAGE_LINES = 36, 10
  end
end

local function style_box(obj, bg, radius, border)
  if not obj then return end
  pcall(lv_obj_set_style_bg_color, obj, bg, MAIN)
  pcall(lv_obj_set_style_bg_opa, obj, 255, MAIN)
  pcall(lv_obj_set_style_border_width, obj, border and 1 or 0, MAIN)
  if border then pcall(lv_obj_set_style_border_color, obj, border, MAIN) end
  pcall(lv_obj_set_style_radius, obj, radius or 0, MAIN)
  pcall(lv_obj_set_style_pad_all, obj, 0, MAIN)
end

local function make_label(parent, x, y, w, h, text, color, font, align)
  local obj = lv_label_create(parent)
  pcall(lv_obj_set_pos, obj, x, y)
  pcall(lv_obj_set_size, obj, w, h)
  pcall(lv_label_set_long_mode, obj, rawget(_G, "LV_LABEL_LONG_CLIP") or 0)
  pcall(lv_obj_set_style_text_color, obj, color or 0xE9E4D8, MAIN)
  pcall(lv_obj_set_style_text_opa, obj, 255, MAIN)
  if font then pcall(lv_obj_set_style_text_font, obj, font, MAIN) end
  pcall(lv_obj_set_style_text_align, obj, align or ALIGN_LEFT, MAIN)
  pcall(lv_label_set_text, obj, text or "")
  return obj
end

local function set_text(obj, text)
  if obj then pcall(lv_label_set_text, obj, tostring(text or "")) end
end

function APP:build_ui()
  if not lv_scr_act then return end
  self:load_font()
  local root = lv_scr_act()
  pcall(lv_obj_clean, root)
  style_box(root, 0x0A0907, 0, nil)

  local header = lv_obj_create(root)
  pcall(lv_obj_set_pos, header, 8, 7)
  pcall(lv_obj_set_size, header, 304, 27)
  style_box(header, 0x17130E, 7, 0x322A20)
  self.ui.title = make_label(header, 8, 5, 286, 18, T("app_title"), 0xF1C97A, self.font, ALIGN_LEFT)
  if LANGUAGE == "ja" or LANGUAGE == "zh-TW" then pcall(lv_obj_set_style_transform_zoom, self.ui.title, 224, MAIN) end

  self.ui.body = make_label(root, 12, 39, 296, 174, T("empty"), 0xE9E4D8, self.body_font, ALIGN_LEFT)
  pcall(lv_obj_set_style_text_line_space, self.ui.body, 1, MAIN)
  if lv_img_create then
    self.ui.image = lv_img_create(root)
    if lv_img_set_antialias then pcall(lv_img_set_antialias, self.ui.image, true) end
    if lv_obj_add_flag then pcall(lv_obj_add_flag, self.ui.image, rawget(_G, "LV_OBJ_FLAG_HIDDEN") or 1) end
  end
  self:apply_appearance(self.font_size, self.text_color, false)

  local footer = lv_obj_create(root)
  pcall(lv_obj_set_pos, footer, 8, 216)
  pcall(lv_obj_set_size, footer, 304, 19)
  style_box(footer, 0x17130E, 6, 0x322A20)
  self.ui.chapter = make_label(footer, 7, 2, 220, 15, T("waiting"), 0xB7AA95, self.font, ALIGN_LEFT)
  pcall(lv_obj_set_style_transform_zoom, self.ui.chapter, 208, MAIN)
  self.ui.hint = make_label(footer, 229, 2, 67, 15, "0.0%", 0xF1C97A, FONT_SMALL, ALIGN_CENTER)

  -- Menu overlay: true black remains optically transparent on the device;
  -- all structure is expressed with thin white strokes only.
  local menu = lv_obj_create(root)
  pcall(lv_obj_set_pos, menu, 7, 6)
  pcall(lv_obj_set_size, menu, 306, 229)
  style_box(menu, 0x000000, 4, 0xFFFFFF)
  self.ui.menu = menu
  self.ui.menu_title = make_label(menu, 10, 7, 286, 20, T("toc"), 0xFFFFFF, self.font, ALIGN_LEFT)
  self.ui.menu_count = make_label(menu, 210, 9, 76, 15, T("items", 0), 0xFFFFFF, FONT_SMALL, ALIGN_CENTER)
  self.ui.menu_rows = {}
  for i = 1, 7 do
    local row = lv_obj_create(menu)
    pcall(lv_obj_set_pos, row, 9, 31 + (i - 1) * 25)
    pcall(lv_obj_set_size, row, 286, 22)
    style_box(row, 0x000000, 2, 0x555555)
    local number = make_label(row, 5, 3, 34, 16, "", 0xA0A0A0, FONT_SMALL, ALIGN_CENTER)
    local text = make_label(row, 42, 2, 236, 18, "", 0xFFFFFF, self.font, ALIGN_LEFT)
    self.ui.menu_rows[i] = { box = row, number = number, text = text }
  end
  self.ui.menu_hint = make_label(menu, 9, 209, 286, 15, T("menu_hint"), 0xFFFFFF, FONT_SMALL, ALIGN_CENTER)
  if lv_obj_add_flag then pcall(lv_obj_add_flag, menu, rawget(_G, "LV_OBJ_FLAG_HIDDEN") or 1) end
  self:update_ui()
end

function APP:load_state()
  local state = json_decode(read_small(STATE_PATH, 65536)) or {}
  self.saved = state
  self.font_size = tonumber(state.font_size) == 16 and 16 or 18
  self.text_color = normalize_text_color(state.text_color)
end

function APP:save_state_now()
  local history = {}
  local first = math.max(1, #self.history - 31)
  for i = first, #self.history do history[#history + 1] = self.history[i] end
  local raw = json_encode({
    path = self.current and self.current.path or nil,
    size = self.current and self.current.size or nil,
    offset = self.offset,
    history = history,
    font_size = self.font_size,
    text_color = string.format("#%06X", self.text_color),
    saved_ms = now_ms(),
  })
  if raw then write_text(STATE_PATH, raw) end
end

function APP:apply_appearance(font_size, text_color, rerender)
  self.font_size = tonumber(font_size) == 16 and 16 or 18
  self.text_color = normalize_text_color(text_color or self.text_color)
  if self.font_size == 16 then
    PAGE_CELLS, PAGE_LINES = 36, 10
    if self.ui.body then pcall(lv_obj_set_style_text_font, self.ui.body, self.font, MAIN) end
  else
    PAGE_CELLS, PAGE_LINES = 32, 9
    if self.ui.body then pcall(lv_obj_set_style_text_font, self.ui.body, self.body_font, MAIN) end
  end
  if self.ui.body then pcall(lv_obj_set_style_text_color, self.ui.body, self.text_color, MAIN) end
  if rerender and self.current then self:show_offset(self.offset, true) else self:schedule_save() end
  return true
end

function APP:schedule_save()
  local old = self.timers.save
  if old then pcall(function() old:stop() old:unregister() end) end
  if not tmr or not tmr.create then self:save_state_now(); return end
  local timer = tmr.create()
  self.timers.save = timer
  timer:alarm(900, tmr.ALARM_SINGLE or 0, function()
    if APP.running then APP:save_state_now() end
    APP.timers.save = nil
  end)
end

function APP:refresh_library()
  ensure_dir(BOOKS_DIR)
  ensure_dir(INDEX_DIR)
  local books = {}
  if file and file.listdir then
    local ok, entries = pcall(file.listdir, BOOKS_DIR)
    if ok and type(entries) == "table" then
      for _, entry in ipairs(entries) do
        local name = type(entry) == "table" and tostring(entry.name or "") or tostring(entry or "")
        local lower = name:lower()
        if name:sub(1, 1) ~= "." and not (type(entry) == "table" and entry.is_dir) and (lower:match("%.txt$") or lower:match("%.md$") or lower:match("%.epubbook$")) then
          local path = (type(entry) == "table" and entry.path) or (BOOKS_DIR .. "/" .. name)
          path = safe_book_path(path)
          if path then
            local book = lower:match("%.epubbook$") and load_epub_book(path) or { format = "text", name = display_name(path), file_name = path_name(path), path = path, size = file_size(path, entry) }
            if book and book.size > 0 then books[#books + 1] = book end
          end
        end
      end
    end
  end
  table.sort(books, function(a, b) return a.file_name:lower() < b.file_name:lower() end)
  self.books = books
  return books
end

function APP:prepare_epub_cache(cache_dir)
  cache_dir = safe_epub_cache_path(cache_dir)
  if not cache_dir or cache_dir == BOOKS_DIR .. "/.epub/" then return false, T("invalid_path") end
  ensure_dir(BOOKS_DIR .. "/.epub")
  ensure_dir(cache_dir)
  ensure_dir(cache_dir .. "/sections")
  ensure_dir(cache_dir .. "/images")
  return true
end

function APP:save_partial_index(idx)
  idx = idx or self.indexer
  if not idx or not idx.book or idx.bytes_read <= 0 then return false end
  local fingerprint = idx.fingerprint or book_fingerprint(idx.book)
  if not fingerprint then return false end
  local pending = tostring(idx.pending or ""):sub(1, 512)
  local parts = {
    "EBP1",
    pack_u32(idx.book.size),
    pack_u32(fingerprint),
    pack_u32(idx.bytes_read),
    pack_u32(idx.crc),
    pack_u32(idx.line_start),
    pack_u16(#pending),
    pack_u16(#idx.chapters),
    pending,
  }
  for _, chapter in ipairs(idx.chapters) do
    local title = utf8_clip(chapter.title or "", 42)
    parts[#parts + 1] = pack_u32(chapter.offset)
    parts[#parts + 1] = pack_u16(#title)
    parts[#parts + 1] = title
  end
  return write_text(partial_index_path(idx.book), table.concat(parts))
end

function APP:load_partial_index(book, fd)
  local function failed(reason)
    self.partial_debug = tostring(reason or "invalid")
    return nil
  end
  local raw = read_small(partial_index_path(book), 1048576)
  if not raw or raw:sub(1, 4) ~= "EBP1" then return failed("missing-or-magic") end
  local pos, stored_size, stored_fingerprint, bytes_read, crc, line_start, pending_len, chapter_count = 5
  stored_size, pos = unpack_u32(raw, pos)
  stored_fingerprint, pos = unpack_u32(raw, pos)
  bytes_read, pos = unpack_u32(raw, pos)
  crc, pos = unpack_u32(raw, pos)
  line_start, pos = unpack_u32(raw, pos)
  pending_len, pos = unpack_u16(raw, pos)
  chapter_count, pos = unpack_u16(raw, pos)
  if stored_size ~= tonumber(book.size) then return failed("size:" .. tostring(stored_size) .. "/" .. tostring(book.size)) end
  if not bytes_read or bytes_read <= 0 or bytes_read > book.size then return failed("offset:" .. tostring(bytes_read)) end
  if not pending_len or pending_len > 512 or not chapter_count or chapter_count < 1 or chapter_count > MAX_CHAPTERS then return failed("counts:" .. tostring(pending_len) .. "/" .. tostring(chapter_count)) end
  local fingerprint = book_fingerprint(book)
  if not fingerprint or fingerprint ~= stored_fingerprint then return failed("fingerprint:" .. tostring(fingerprint) .. "/" .. tostring(stored_fingerprint)) end
  if pos + pending_len - 1 > #raw then return failed("pending-bounds") end
  local pending = raw:sub(pos, pos + pending_len - 1)
  pos = pos + pending_len
  local chapters = {}
  for i = 1, chapter_count do
    local offset, title_len
    offset, pos = unpack_u32(raw, pos)
    title_len, pos = unpack_u16(raw, pos)
    if not offset or not title_len or title_len > 512 or pos + title_len - 1 > #raw then return failed("entry:" .. tostring(i)) end
    local title = raw:sub(pos, pos + title_len - 1)
    pos = pos + title_len
    chapters[#chapters + 1] = { offset = offset, title = title ~= "" and title or T("chapter", i) }
  end
  local ok = pcall(function() fd:seek("set", bytes_read) end)
  if not ok then return failed("seek") end
  self.partial_debug = "loaded"
  return {
    book = book, fd = fd, bytes_read = bytes_read, line_start = line_start or bytes_read,
    pending = pending, crc = signed_i32(crc or 0xFFFFFFFF), fingerprint = fingerprint,
    chapters = chapters, next_checkpoint = math.min(100, math.floor(bytes_read * 100 / book.size / 10 + 1) * 10),
  }
end

function APP:cancel_index()
  if not self.indexer then return end
  self:save_partial_index(self.indexer)
  close_fd(self.indexer.fd)
  self.indexer.fd = nil
  if self.indexer.timer then pcall(function() self.indexer.timer:stop() self.indexer.timer:unregister() end) end
  self.indexer = nil
end

function APP:load_index(book)
  local raw = read_small(index_path(book), 1048576)
  if not raw or raw:sub(1, 4) ~= INDEX_MAGIC then return false end
  local pos, stored_size, stored_crc, stored_fingerprint, chapter_count = 5
  stored_size, pos = unpack_u32(raw, pos)
  stored_crc, pos = unpack_u32(raw, pos)
  stored_fingerprint, pos = unpack_u32(raw, pos)
  chapter_count, pos = unpack_u16(raw, pos)
  if not stored_size or stored_size ~= tonumber(book.size) or not chapter_count or chapter_count < 1 or chapter_count > MAX_CHAPTERS then return false end
  local fingerprint = book_fingerprint(book)
  if not fingerprint or fingerprint ~= stored_fingerprint then return false end
  local chapters = {}
  for i = 1, chapter_count do
    local offset, title_len
    offset, pos = unpack_u32(raw, pos)
    title_len, pos = unpack_u16(raw, pos)
    if not offset or not title_len or title_len > 512 or pos + title_len - 1 > #raw then return false end
    local title = raw:sub(pos, pos + title_len - 1)
    pos = pos + title_len
    if offset >= book.size then return false end
    chapters[#chapters + 1] = { offset = math.floor(offset), title = utf8_clip(title ~= "" and title or T("chapter", i), 42) }
  end
  if #chapters == 0 then chapters[1] = { offset = 0, title = T("start") } end
  self.chapters = chapters
  self.file_crc = stored_crc
  self.file_fingerprint = stored_fingerprint
  self.index_progress = 100
  self.index_status = "ready"
  self.index_message = T("index_loaded")
  return true
end

function APP:index_line(indexer, line, offset)
  local title = chapter_title(line)
  if not title or #indexer.chapters >= MAX_CHAPTERS then return end
  local last = indexer.chapters[#indexer.chapters]
  if last and (offset - last.offset) < 12 then return end
  indexer.chapters[#indexer.chapters + 1] = { offset = offset, title = title }
end

function APP:finish_index(error_message)
  local idx = self.indexer
  if not idx then return end
  close_fd(idx.fd)
  idx.fd = nil
  if idx.timer then pcall(function() idx.timer:stop() idx.timer:unregister() end) end
  if error_message then
    self.index_status = "error"
    self.index_message = tostring(error_message)
  else
    if #idx.chapters == 0 then idx.chapters[1] = { offset = 0, title = T("start") } end
    self.chapters = idx.chapters
    self.index_progress = 100
    local output, written = nil, 0
    local ok_write, fingerprint, file_crc = pcall(function()
      local fp = idx.fingerprint or book_fingerprint(idx.book)
      if not fp then error("fingerprint") end
      local crc = unsigned_u32((~idx.crc) & 0xFFFFFFFF)
      output = file and file.open and file.open(index_path(idx.book), "w+")
      if not output then error("open-index") end
      local header = INDEX_MAGIC .. pack_u32(idx.book.size) .. pack_u32(crc) .. pack_u32(fp) .. pack_u16(#idx.chapters)
      output:write(header)
      written = #header
      for _, chapter in ipairs(idx.chapters) do
        local title = utf8_clip(chapter.title or "", 42)
        local entry = pack_u32(chapter.offset) .. pack_u16(#title) .. title
        output:write(entry)
        written = written + #entry
      end
      output:flush()
      return fp, crc
    end)
    close_fd(output)
    if not ok_write then
      self.index_status = "error"
      self.index_message = T("index_failed")
      self.index_debug = "write-error:" .. tostring(fingerprint)
    else
      self.index_status = "ready"
      self.index_message = T("index_done", #idx.chapters)
      self.file_crc = file_crc
      self.file_fingerprint = fingerprint
      self.index_debug = "saved:" .. tostring(written)
      if file and file.remove then pcall(file.remove, partial_index_path(idx.book)) end
    end
  end
  self.indexer = nil
  self:update_ui()
end

function APP:index_step()
  local idx = self.indexer
  if not idx or not idx.fd then return end
  local ok, chunk = pcall(function() return idx.fd:read(INDEX_CHUNK_BYTES) end)
  if not ok then
    idx.read_errors = (idx.read_errors or 0) + 1
    if idx.read_errors <= 8 then return end
    self:save_partial_index(idx)
    self.index_debug = "read-failed-at:" .. tostring(idx.bytes_read)
    self:finish_index(T("index_failed"))
    return
  end
  idx.read_errors = 0
  if not chunk or #chunk == 0 then
    if #idx.pending > 0 then self:index_line(idx, idx.pending, idx.line_start) end
    self:finish_index(nil)
    return
  end
  local base = idx.bytes_read
  local pos = 1
  while true do
    local newline = chunk:find("\n", pos, true)
    if not newline then
      if #idx.pending < 512 then idx.pending = idx.pending .. chunk:sub(pos, pos + (511 - #idx.pending)) end
      break
    end
    if #idx.pending < 512 then idx.pending = idx.pending .. chunk:sub(pos, math.min(newline - 1, pos + (511 - #idx.pending))) end
    self:index_line(idx, idx.pending, idx.line_start)
    idx.pending = ""
    idx.line_start = base + newline
    pos = newline + 1
  end
  idx.bytes_read = idx.bytes_read + #chunk
  idx.crc = crc32_update(idx.crc, chunk)
  local progress = idx.book.size > 0 and math.min(99, math.floor(idx.bytes_read * 100 / idx.book.size)) or 99
  self.index_progress = progress
  if progress >= (idx.next_checkpoint or 10) then
    self:save_partial_index(idx)
    idx.next_checkpoint = math.min(100, math.floor(progress / 10 + 1) * 10)
  end
  if progress ~= idx.last_ui_progress then
    idx.last_ui_progress = progress
    self.index_message = T("index_build", progress, #idx.chapters)
    self:update_ui()
  end
end

function APP:start_index(book, force)
  self:cancel_index()
  if book and book.format == "epub" then
    self.chapters = {}
    for i, section in ipairs(book.sections or {}) do self.chapters[i] = { offset = section.offset, title = section.title } end
    self.index_status = "ready"
    self.index_progress = 100
    self.index_message = T("epub_loaded", #self.chapters)
    self.file_crc = nil
    return #self.chapters > 0
  end
  if not force and self:load_index(book) then return true end
  if force and file and file.remove then
    pcall(file.remove, index_path(book))
    pcall(file.remove, partial_index_path(book))
  end
  local fd = file and file.open and file.open(book.path, "r")
  if not fd then
    self.index_status = "error"
    self.index_message = T("open_failed")
    return false
  end
  local idx = not force and self:load_partial_index(book, fd) or nil
  local resumed = idx ~= nil
  if not idx then
    idx = { book = book, fd = fd, bytes_read = 0, line_start = 0, pending = "", crc = 0xFFFFFFFF, fingerprint = book_fingerprint(book), next_checkpoint = 10, chapters = { { offset = 0, title = T("start") } } }
  end
  self.indexer = idx
  self.chapters = idx.chapters
  self.index_progress = resumed and math.floor(idx.bytes_read * 100 / book.size) or 0
  self.index_status = "scanning"
  self.index_message = resumed and T("index_resume", self.index_progress, #idx.chapters) or T("index_start")
  if tmr and tmr.create then
    idx.timer = tmr.create()
    idx.timer:alarm(5, tmr.ALARM_AUTO or 1, function() if APP.running then APP:index_step() end end)
  else
    while self.indexer do self:index_step() end
  end
  return true
end

local function next_utf8(data, pos)
  local b1 = data:byte(pos)
  if not b1 then return nil end
  if b1 < 0x80 then return data:sub(pos, pos), 1, 1 end
  local n = b1 >= 0xF0 and 4 or b1 >= 0xE0 and 3 or b1 >= 0xC2 and 2 or 1
  if pos + n - 1 > #data then return nil end
  if n == 1 then return "?", 1, 1 end
  for i = 1, n - 1 do
    local b = data:byte(pos + i)
    if not b or b < 0x80 or b >= 0xC0 then return "?", 1, 1 end
  end
  return data:sub(pos, pos + n - 1), n, 2
end

function APP:read_page(offset)
  if not self.current then return "", nil end
  offset = math.max(0, math.min(math.floor(tonumber(offset) or 0), self.current.size))
  local chapter_index = self:chapter_index_at(offset)
  local chapter_end = self.chapters[chapter_index + 1] and self.chapters[chapter_index + 1].offset or self.current.size
  local source_path, source_offset = self.current.path, offset
  if self.current.format == "epub" then
    local section = self.current.sections and self.current.sections[chapter_index]
    if not section then return T("epub_invalid"), nil end
    source_path = section.path
    source_offset = math.max(0, offset - section.offset)
    chapter_end = section.offset + section.size
  end
  local fd = file and file.open and file.open(source_path, "r")
  if not fd then return T("open_failed"), nil end
  local read_bytes = math.min(PAGE_READ_BYTES, math.max(0, chapter_end - offset))
  local ok, data = pcall(function() fd:seek("set", source_offset) return fd:read(read_bytes) end)
  close_fd(fd)
  if not ok or type(data) ~= "string" then return T("read_failed"), nil end
  local sample, zeroes = math.min(#data, 768), 0
  for i = 1, sample do if data:byte(i) == 0 then zeroes = zeroes + 1 end end
  if sample > 32 and zeroes * 12 > sample then return T("encoding_bad"), nil end
  local pos = 1
  if source_offset == 0 and data:sub(1, 3) == string.char(239, 187, 191) then pos = 4 end
  local out, line, cells, leading_blanks = {}, 1, 0, 0
  while pos <= #data and line <= PAGE_LINES do
    if self.current.format == "epub" and data:sub(pos, pos + 9) == "[[EPUBIMG:" then
      local marker_end = data:find("]]", pos + 10, true)
      local image_index = marker_end and tonumber(data:sub(pos + 10, marker_end - 1)) or nil
      local image = image_index and self.current.images and self.current.images[image_index] or nil
      if marker_end and image then
        if #out > 0 then break end
        local consumed_end = marker_end + 1
        while consumed_end + 1 <= #data do
          local next_byte = data:byte(consumed_end + 1)
          if next_byte == 10 or next_byte == 13 then consumed_end = consumed_end + 1 else break end
        end
        local image_next = offset + consumed_end
        if image_next >= chapter_end or image_next >= self.current.size then image_next = nil end
        return "", image_next, image
      end
    end
    local b = data:byte(pos)
    if b == 13 or b == 10 then
      local consumed = 1
      if b == 13 and data:byte(pos + 1) == 10 then consumed = 2 end
      pos = pos + consumed
      if cells == 0 and #out == 0 and leading_blanks < 2 then leading_blanks = leading_blanks + 1
      else
        if line >= PAGE_LINES then break end
        out[#out + 1] = "\n"
        line = line + 1
        cells = 0
      end
    elseif b == 9 then
      local width = 4 - (cells % 4)
      if cells + width > PAGE_CELLS then
        if line >= PAGE_LINES then break end
        out[#out + 1] = "\n"; line = line + 1; cells = 0
      end
      out[#out + 1] = " "; cells = cells + width; pos = pos + 1
    elseif b and b < 32 then
      pos = pos + 1
    else
      local ch, bytes, width = next_utf8(data, pos)
      if not ch then break end
      if cells + width > PAGE_CELLS then
        if line >= PAGE_LINES then break end
        out[#out + 1] = "\n"; line = line + 1; cells = 0
      end
      out[#out + 1] = ch
      cells = cells + width
      pos = pos + bytes
    end
  end
  local next_offset = offset + pos - 1
  if next_offset >= chapter_end or next_offset >= self.current.size or next_offset <= offset then next_offset = nil end
  local text = table.concat(out)
  if text == "" and offset >= self.current.size then text = T("end_book") end
  return text, next_offset, nil
end

function APP:chapter_index_at(offset)
  local chapters = self.chapters
  if #chapters == 0 then return 1 end
  local lo, hi, result = 1, #chapters, 1
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    if chapters[mid].offset <= offset then result = mid; lo = mid + 1 else hi = mid - 1 end
  end
  return result
end

function APP:menu_items()
  if self.menu.kind == "library" then return self.books end
  return self.chapters
end

function APP:update_menu()
  if not self.ui.menu or not self.menu.open then return end
  local items = self:menu_items()
  local count = #items
  if count <= 0 then
    self.menu.selected, self.menu.first = 1, 1
  else
    self.menu.selected = math.max(1, math.min(count, self.menu.selected or 1))
    if self.menu.selected < self.menu.first then self.menu.first = self.menu.selected end
    if self.menu.selected > self.menu.first + 6 then self.menu.first = self.menu.selected - 6 end
    self.menu.first = math.max(1, math.min(math.max(1, count - 6), self.menu.first or 1))
  end
  set_text(self.ui.menu_title, self.menu.kind == "library" and T("library") or T("toc"))
  local suffix = self.menu.kind == "toc" and self.index_status == "scanning" and (" · " .. self.index_progress .. "%") or ""
  set_text(self.ui.menu_count, T("items", count) .. suffix)
  for row_index, row in ipairs(self.ui.menu_rows or {}) do
    local index = self.menu.first + row_index - 1
    local item = items[index]
    local selected = item and index == self.menu.selected
    pcall(lv_obj_set_style_border_width, row.box, selected and 2 or 1, MAIN)
    pcall(lv_obj_set_style_border_color, row.box, selected and 0xFFFFFF or 0x555555, MAIN)
    pcall(lv_obj_set_style_bg_color, row.box, 0x000000, MAIN)
    if item then
      set_text(row.number, string.format("%02d", index))
      local title = self.menu.kind == "library" and item.name or item.title
      set_text(row.text, utf8_clip(title or "", 20))
      pcall(lv_obj_set_style_text_color, row.number, selected and 0xFFFFFF or 0x888888, MAIN)
      pcall(lv_obj_set_style_text_color, row.text, 0xFFFFFF, MAIN)
    else
      set_text(row.number, "")
      set_text(row.text, "")
    end
  end
end

function APP:open_menu(kind)
  kind = kind == "library" and "library" or "toc"
  self.menu.kind = kind
  self.menu.open = true
  if kind == "toc" then
    self.menu.selected = self.current and self:chapter_index_at(self.offset) or 1
  else
    self.menu.selected = 1
    if self.current then for i, book in ipairs(self.books) do if book.path == self.current.path then self.menu.selected = i; break end end end
  end
  self.menu.first = math.max(1, self.menu.selected - 3)
  if lv_obj_clear_flag then pcall(lv_obj_clear_flag, self.ui.menu, rawget(_G, "LV_OBJ_FLAG_HIDDEN") or 1) end
  self:update_menu()
end

function APP:close_menu()
  self.menu.open = false
  if lv_obj_add_flag then pcall(lv_obj_add_flag, self.ui.menu, rawget(_G, "LV_OBJ_FLAG_HIDDEN") or 1) end
end

function APP:switch_menu()
  self:open_menu(self.menu.kind == "toc" and "library" or "toc")
end

function APP:menu_move(delta)
  local items = self:menu_items()
  if #items == 0 then return end
  self.menu.selected = self.menu.selected + (delta or 1)
  if self.menu.selected < 1 then self.menu.selected = #items end
  if self.menu.selected > #items then self.menu.selected = 1 end
  self:update_menu()
end

function APP:menu_confirm()
  local items = self:menu_items()
  local item = items[self.menu.selected]
  if not item then return false, T("no_choice") end
  if self.menu.kind == "library" then
    local ok, err = self:open_book(item.path, false)
    if ok then self:close_menu() end
    return ok, err
  end
  local ok, err = self:jump_chapter(self.menu.selected)
  if ok then self:close_menu() end
  return ok, err
end

function APP:update_ui()
  if not self.ui.title then return end
  if not self.current then
    if self.ui.image and lv_obj_add_flag then pcall(lv_obj_add_flag, self.ui.image, rawget(_G, "LV_OBJ_FLAG_HIDDEN") or 1) end
    if self.ui.body and lv_obj_clear_flag then pcall(lv_obj_clear_flag, self.ui.body, rawget(_G, "LV_OBJ_FLAG_HIDDEN") or 1) end
    set_text(self.ui.title, T("app_title"))
    set_text(self.ui.body, #self.books == 0 and T("empty") or T("choose"))
    set_text(self.ui.chapter, self.index_message ~= "" and self.index_message or T("waiting"))
    set_text(self.ui.hint, "0.0%")
    return
  end
  local percent = self.current.size > 0 and self.offset * 100 / self.current.size or 0
  local hidden = rawget(_G, "LV_OBJ_FLAG_HIDDEN") or 1
  if self.page_image and self.ui.image and lv_img_set_src then
    if self.ui.body and lv_obj_add_flag then pcall(lv_obj_add_flag, self.ui.body, hidden) end
    local source = self.page_image.path
    if source:sub(1, 4) == "/sd/" then source = "S:/" .. source:sub(5) end
    pcall(lv_img_set_src, self.ui.image, source)
    pcall(lv_obj_set_pos, self.ui.image, 12 + math.floor((296 - self.page_image.width) / 2), 39 + math.floor((174 - self.page_image.height) / 2))
    if lv_obj_clear_flag then pcall(lv_obj_clear_flag, self.ui.image, hidden) end
  else
    if self.ui.image and lv_obj_add_flag then pcall(lv_obj_add_flag, self.ui.image, hidden) end
    if self.ui.body and lv_obj_clear_flag then pcall(lv_obj_clear_flag, self.ui.body, hidden) end
    set_text(self.ui.body, self.page_text)
  end
  local ci = self:chapter_index_at(self.offset)
  local chapter = self.chapters[ci]
  local footer = chapter and utf8_clip(chapter.title, 17) or T("main_body")
  set_text(self.ui.title, footer)
  set_text(self.ui.chapter, utf8_clip(self.current.name, 20))
  set_text(self.ui.hint, string.format("%.1f%%", math.min(100, percent)))
  if self.menu.open then self:update_menu() end
end

function APP:show_offset(offset, clear_history)
  if not self.current then return false, T("no_book") end
  offset = math.max(0, math.min(math.floor(tonumber(offset) or 0), self.current.size))
  local text, next_offset, page_image = self:read_page(offset)
  if clear_history then self.history = {} end
  self.offset = offset
  self.page_text = text
  self.page_image = page_image
  self.next_offset = next_offset
  self:update_ui()
  self:schedule_save()
  return true
end

function APP:next_page()
  local target = self.next_offset
  if not target then
    local chapter_index = self:chapter_index_at(self.offset)
    local next_chapter = self.chapters[chapter_index + 1]
    if next_chapter then target = next_chapter.offset end
  end
  if not target then return false, T("finished") end
  self.history[#self.history + 1] = self.offset
  if #self.history > 128 then table.remove(self.history, 1) end
  return self:show_offset(target, false)
end

function APP:prev_page()
  local offset = table.remove(self.history)
  if not offset then
    local ci = self:chapter_index_at(self.offset)
    local floor_offset = self.chapters[ci] and self.chapters[ci].offset or 0
    offset = math.max(floor_offset, self.offset - 1150)
  end
  if offset == self.offset then return false, T("first") end
  return self:show_offset(offset, false)
end

function APP:jump_chapter(index)
  index = math.floor(tonumber(index) or 1)
  local item = self.chapters[index]
  if not item then return false, T("chapter_missing") end
  return self:show_offset(item.offset, true)
end

function APP:next_chapter(delta)
  local current = self:chapter_index_at(self.offset)
  return self:jump_chapter(math.max(1, math.min(#self.chapters, current + (delta or 1))))
end

function APP:open_book(path, force_index)
  path = safe_book_path(path)
  if not path then return false, T("invalid_book") end
  local selected
  for _, book in ipairs(self.books) do if book.path == path then selected = book; break end end
  if not selected then
    selected = path:lower():match("%.epubbook$") and load_epub_book(path) or { format = "text", path = path, file_name = path_name(path), name = display_name(path), size = file_size(path) }
    if not selected then return false, T("epub_invalid") end
    if selected.size <= 0 then return false, T("missing_book") end
  end
  self.current = selected
  self.chapters = {}
  self:start_index(selected, force_index == true)
  local offset, history = 0, {}
  if self.saved and self.saved.path == path and tonumber(self.saved.size) == tonumber(selected.size) then
    offset = math.max(0, math.min(tonumber(self.saved.offset) or 0, selected.size))
    if type(self.saved.history) == "table" then for _, value in ipairs(self.saved.history) do if tonumber(value) then history[#history + 1] = tonumber(value) end end end
  end
  self.history = history
  return self:show_offset(offset, false)
end

function APP:remove_book(path)
  path = safe_book_path(path)
  if not path then return false, T("invalid_path") end
  local target
  for _, book in ipairs(self.books) do if book.path == path then target = book; break end end
  if not target then return false, T("book_missing") end
  if self.current and self.current.path == path then self:cancel_index(); self.current = nil; self.chapters = {}; self.page_text = ""; self.page_image = nil end
  local ok, removed = false, false
  if file and file.remove then ok, removed = pcall(file.remove, path) end
  ok = ok and removed ~= false
  if ok then
    if target.format == "epub" and target.cache_dir and file then
      -- Delete only paths that were validated while loading this manifest.
      -- Avoid a recursive directory walk so one malformed/stale entry can
      -- never affect another book's sibling cache.
      if file.remove then
        for _, section in ipairs(target.sections or {}) do if safe_epub_cache_path(section.path) then pcall(file.remove, section.path) end end
        for _, image in pairs(target.images or {}) do if safe_epub_cache_path(image.path) then pcall(file.remove, image.path) end end
      end
      if file.rmdir then
        pcall(file.rmdir, target.cache_dir .. "/sections")
        pcall(file.rmdir, target.cache_dir .. "/images")
        pcall(file.rmdir, target.cache_dir)
      end
    else
      pcall(file.remove, index_path(target))
      pcall(file.remove, partial_index_path(target))
    end
  end
  self:refresh_library()
  if not self.current and #self.books > 0 then self:open_book(self.books[1].path, false) else self:update_ui() end
  if ok then return true, nil end
  return false, T("delete_failed")
end

function APP:chapters_slice(start, limit)
  start = math.max(1, math.floor(tonumber(start) or 1))
  limit = math.max(1, math.min(200, math.floor(tonumber(limit) or 80)))
  local items = {}
  for i = start, math.min(#self.chapters, start + limit - 1) do
    local item = self.chapters[i]
    items[#items + 1] = { index = i, title = item.title, offset = item.offset }
  end
  return { ok = true, start = start, limit = limit, total = #self.chapters, items = items, scanning = self.index_status == "scanning", progress = self.index_progress }
end

function APP:snapshot(message)
  local current_chapter = self.current and self:chapter_index_at(self.offset) or 0
  return {
    ok = true,
    version = self.version,
    language = self.language,
    books_dir = BOOKS_DIR,
    books = self.books,
    current = self.current,
    offset = self.offset,
    next_available = self.next_offset ~= nil or (self.current and self.chapters[self:chapter_index_at(self.offset) + 1] ~= nil) or false,
    previous_available = #self.history > 0 or self.offset > 0,
    progress = self.current and self.current.size > 0 and self.offset * 100 / self.current.size or 0,
    current_chapter = current_chapter,
    chapter_count = #self.chapters,
    chapter_title = self.chapters[current_chapter] and self.chapters[current_chapter].title or "",
    index_status = self.index_status,
    index_progress = self.index_progress,
    index_message = self.index_message,
    index_file = self.current and (self.current.format == "epub" and self.current.path or index_path(self.current)) or nil,
    file_crc = self.file_crc,
    partial_debug = self.partial_debug,
    index_debug = self.index_debug,
    font_size = self.font_size,
    text_color = string.format("#%06X", self.text_color),
    page_kind = self.page_image and "image" or "text",
    page_image = self.page_image and self.page_image.path or nil,
    message = message,
  }
end

function APP:bind_keys()
  if not key or not key.on then return end
  local function move(delta)
    if APP.menu.open then APP:menu_move(delta)
    elseif delta < 0 then APP:prev_page()
    else APP:next_page() end
  end

  -- Keep these four event branches identical to Launcher. The firmware turns
  -- tilt/gyro gestures into key.LEFT/key.RIGHT, so delay, threshold and repeat
  -- cadence stay exactly the same without a second IMU filter in this app.
  key.on(key.LEFT, function(event, ts_ms)
    if event == key.START then
      move(-1)
    elseif event == key.LONG_START then
      APP.repeat_left = 0
      move(-1)
    elseif event == key.LONG_REPEAT then
      APP.repeat_left = APP.repeat_left + 1
      if (APP.repeat_left % 3) == 0 then move(-1) end
    elseif event == key.LONG_END then
      APP.repeat_left = 0
    end
  end)

  key.on(key.RIGHT, function(event, ts_ms)
    if event == key.START then
      move(1)
    elseif event == key.LONG_START then
      APP.repeat_right = 0
      move(1)
    elseif event == key.LONG_REPEAT then
      APP.repeat_right = APP.repeat_right + 1
      if (APP.repeat_right % 3) == 0 then move(1) end
    elseif event == key.LONG_END then
      APP.repeat_right = 0
    end
  end)

  if key.UP then
    key.on(key.UP, function(event)
      if event == key.SHORT then
        if APP.menu.open then APP:menu_confirm() else APP:open_menu("toc") end
      end
    end)
  end
  if key.DOWN then
    key.on(key.DOWN, function(event)
      if event == key.SHORT then
        if APP.menu.open then APP:switch_menu() else APP:open_menu("library") end
      end
    end)
  end

  -- Same controller source and 40 ms poll interval used by Launcher.
  local PAD_UP, PAD_DOWN, PAD_LEFT, PAD_RIGHT = 1, 2, 4, 8
  local PAD_A, PAD_B, PAD_SELECT, PAD_START, PAD_HOME = 16, 32, 4096, 8192, 32768
  if controller and controller.state and tmr and tmr.create then
    self.controller_timer = tmr.create()
    self.controller_timer:alarm(40, tmr.ALARM_AUTO or 1, function()
      if not APP.running then return end
      local ok, pad = pcall(function() return controller.state("ble-main") end)
      local buttons = ok and type(pad) == "table" and tonumber(pad.buttons) or 0
      buttons = buttons or 0
      local pressed = buttons & (~APP.controller_buttons)
      APP.controller_buttons = buttons
      if (pressed & (PAD_SELECT | PAD_HOME)) ~= 0 then
        APP:stop("controller-exit")
        if app and app.exit then pcall(function() app.exit() end) end
      elseif (pressed & PAD_LEFT) ~= 0 then
        move(-1)
      elseif (pressed & PAD_RIGHT) ~= 0 then
        move(1)
      elseif (pressed & PAD_UP) ~= 0 then
        if APP.menu.open then APP:menu_move(-1) else APP:open_menu("toc") end
      elseif (pressed & PAD_DOWN) ~= 0 then
        if APP.menu.open then APP:menu_move(1) else APP:open_menu("library") end
      elseif (pressed & PAD_A) ~= 0 then
        if APP.menu.open then APP:menu_confirm() else APP:open_menu("toc") end
      elseif (pressed & PAD_START) ~= 0 then
        if APP.menu.open then APP:switch_menu() else APP:open_menu("library") end
      elseif (pressed & PAD_B) ~= 0 and APP.menu.open then
        APP:close_menu()
      end
    end)
  end
end

function APP:stop(reason)
  if not self.running then return end
  self.running = false
  self:save_state_now()
  self:cancel_index()
  for _, timer in pairs(self.timers) do pcall(function() timer:stop() timer:unregister() end) end
  self.timers = {}
  if self.web and self.web.stop then pcall(function() self.web:stop() end) end
  if key and key.off then pcall(key.off) end
  if self.controller_timer then pcall(function() self.controller_timer:stop() self.controller_timer:unregister() end) end
  self.controller_timer = nil
  if self.font_handle and lv_font_free then pcall(lv_font_free, self.font_handle) end
  if self.body_font_handle and lv_font_free then pcall(lv_font_free, self.body_font_handle) end
  self.font_handle = nil
  self.body_font_handle = nil
end

ensure_dir(BOOKS_DIR)
ensure_dir(INDEX_DIR)
APP:load_state()
APP:refresh_library()
APP:build_ui()
if #APP.books > 0 then
  local path = safe_book_path(APP.saved.path)
  local found = false
  for _, book in ipairs(APP.books) do if book.path == path then found = true; break end end
  APP:open_book(found and path or APP.books[1].path, false)
end
APP:bind_keys()

local ok_web, Web = pcall(dofile, APP_DIR .. "/web.lua")
if ok_web and Web and Web.new then
  local base = (app and app.route_base and app.route_base()) or ("/" .. APP_ID)
  APP.web = Web.new({ app = APP, route_base = base, books_dir = BOOKS_DIR })
  APP.web:start()
else
  APP.index_message = T("web_failed")
  APP:update_ui()
end

return APP
