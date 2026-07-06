local prev = rawget(_G, "MUSIC_PLAYER_APP")
if prev and prev.stop then
  pcall(function()
    prev.stop("reload")
  end)
end

MUSIC_PLAYER_APP = {
  VERSION = "1.12",
  SCREEN_W = 320,
  SCREEN_H = 240,
  APP_DIR = "/sd/apps/mp3_player",
  ASSET_DIR = "/sd/apps/mp3_player/assets",
  FONT_DIR = "/sd/apps/mp3_player/font",
  MUSIC_DIRS = { "/sd/mp3", "/sd/MP3" },
  MODULE_PATH = "/sd/apps/mp3_player/modules/audio.so",
  I2S_ID = 0,
  I2S_BITS = 16,
  DATA_OUT_PIN = 48,
  BUFFER_COUNT = 6,
  BUFFER_LEN = 512,
  I2S_BUFFER_FALLBACKS = {
    { count = 6, len = 512 },
    { count = 4, len = 512 },
    { count = 4, len = 256 },
  },
  PLAY_TASK_CHUNK_BYTES = 4096,
  PLAY_TASK_TIMEOUT_MS = 80,
  PLAY_TASK_STACK_BYTES = 5120,
  PLAY_TASK_PRIORITY = 6,
  PLAY_TASK_CORE = 0,
  PRODUCER_TASK_STACK_BYTES = 6144,
  PRODUCER_TASK_PRIORITY = 5,
  PRODUCER_TASK_CORE = 1,
  PLAY_TICK_MS = 25,
  UI_TICK_MS = 60,
  PROFILE_AUDIO = false,
  PROFILE_LOG_MS = 2000,
  USE_CANVAS_PROGRESS = false,
  WEB_MUSIC_DIR = "/sd/mp3",
  MP3_PREFETCH_TARGET_BYTES = 1 * 1024 * 1024,
  MP3_PREFETCH_READ_BYTES = 16 * 1024,
  MP3_PREFETCH_OPEN_BYTES = 512 * 1024,
  MP3_PREFETCH_UPLOAD_TARGET_BYTES = 2 * 1024 * 1024,
  MP3_PREFETCH_UPLOAD_READ_BYTES = 2 * 1024 * 1024,
  WEB_CHUNK_SIZE = 256 * 1024,
  WEB_UPLOAD_WRITE_BYTES = 16 * 1024,
  WEB_UPLOAD_YIELD_BYTES = 64 * 1024,
  WEB_MAX_FILE_SIZE = 32 * 1024 * 1024,
  WEB_MAX_HANDLERS = 64,
  WEB_DEBUG = false,
  FUNCTION_LOG = true,
  EQ_SETTINGS_FILE = "eq_settings.json",
  EQ_SAVE_DELAY_MS = 1000,
  MP3_FALLBACK_BITRATE = 128000,
}

local APP = MUSIC_PLAYER_APP
local MAIN_STYLE = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local FONT_10 = rawget(_G, "LV_FONT_MONTSERRAT_10") or 10
local FONT_12 = rawget(_G, "LV_FONT_MONTSERRAT_12") or 12
local FONT_14 = rawget(_G, "LV_FONT_MONTSERRAT_14") or 14
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local LABEL_LONG_CLIP = rawget(_G, "LV_LABEL_LONG_CLIP") or rawget(_G, "LABEL_LONG_CLIP")
local CANVAS_FMT = rawget(_G, "LV_IMG_CF_TRUE_COLOR") or rawget(_G, "CANVAS_FMT_TRUE_COLOR")
local EVENT_CLICKED = rawget(_G, "LV_EVENT_CLICKED")
local FLAG_CLICKABLE = rawget(_G, "LV_OBJ_FLAG_CLICKABLE")
local LV_LAYOUT_NONE_VALUE = rawget(_G, "LV_LAYOUT_NONE") or 0

local C = {
  bg = 0xFFFFFF,
  text = 0x000000,
  sub = 0x555555,
  faint = 0x8A8A8A,
  line = 0xD6D6D6,
  accent = 0x111111,
}

local LYRIC_OFFSETS = { -2, -1, 0, 1, 2, 3 }
local LYRIC_CENTER_Y = 54
local LYRIC_WRAP_LIMIT = 15
local LYRIC_LINE_SPACE = 4
local LYRIC_SMALL_LINE_H = 17
local LYRIC_ACTIVE_LINE_H = 21

APP.C = C
APP.MAIN_STYLE = MAIN_STYLE
APP.FONT_10 = FONT_10
APP.FONT_12 = FONT_12
APP.FONT_14 = FONT_14
APP.ALIGN_CENTER = ALIGN_CENTER
APP.LABEL_LONG_CLIP = LABEL_LONG_CLIP
APP.CANVAS_FMT = CANVAS_FMT
APP.EVENT_CLICKED = EVENT_CLICKED
APP.FLAG_CLICKABLE = FLAG_CLICKABLE
APP.LV_LAYOUT_NONE_VALUE = LV_LAYOUT_NONE_VALUE
APP.LYRIC_OFFSETS = LYRIC_OFFSETS
APP.LYRIC_CENTER_Y = LYRIC_CENTER_Y
APP.LYRIC_WRAP_LIMIT = LYRIC_WRAP_LIMIT
APP.LYRIC_LINE_SPACE = LYRIC_LINE_SPACE
APP.LYRIC_SMALL_LINE_H = LYRIC_SMALL_LINE_H
APP.LYRIC_ACTIVE_LINE_H = LYRIC_ACTIVE_LINE_H

APP.running = true
APP.audio = nil
APP.timers = {}
APP.ui = {}
APP.font_handles = {}
APP.tracks = {}
APP.index = 1
APP.prof = nil
APP.web_started = false
APP.upload_logs = {}
APP.needs_rescan = false
APP.rescan_reason = nil


APP.eq_settings = {
  volume = 0.4,
  hpf_freq = 100,
  limiter_dbfs = nil,
  limiter_peak = 31000,
  vbass = true,
  vbass_low_hpf = 50,
  vbass_low_lpf = 180,
  vbass_out_hpf = 100,
  vbass_out_lpf = 600,
  vbass_drive = 3.5,
  vbass_mix = 0.25,
  vbass_even = 1.9,
  vbass_odd = 0.5,
  vbass_solo = false,
  eq = {6.0, 5.9, 3.6, 0.3, -2.6, -0.8, 0.5},
}


APP.state = {
  playing = false,
  opening = false,
  in_tick = false,
  buffering = false,
  buffering_reason = "",
  sample_rate = 44100,
  channels = 2,
  bytes_per_sec = 44100 * 2 * 2,
  file_size = 0,
  bitrate = 0,
  duration_estimated = false,
  pcm_bytes = 0,
  play_task_base_pcm_bytes = 0,
  play_task_last_written_bytes = 0,
  play_task_last_progress_ms = 0,
  play_task_stall_logged_ms = 0,
  eof_advanced = false,
  duration_ms = 0,
  clock_base_ms = 0,
  clock_start_ms = 0,
  angle = 0,
  status = "LOAD",
  error = "",
  lyrics = {},
  lyric_idx = 1,
}
APP.events = {}

local S = APP.state
local scan_tracks
local apply_audio_effects
local web_state

local function call(fn, ...)
  if fn then
    return pcall(fn, ...)
  end
  return false
end

local function log(...)
  if print then
    print("[music_player]", ...)
  end
end

local function web_log(...)
  if APP.WEB_DEBUG then
    log("[web]", ...)
  end
end

local function feature_log(...)
  if APP.FUNCTION_LOG then
    log(...)
  end
end

local function log_now_ms()
  if millis then
    local ok, value = pcall(millis)
    if ok and value then return tonumber(value) or 0 end
  end
  return math.floor((os and os.time and os.time() or 0) * 1000)
end

local function log_bytes(n)
  n = tonumber(n) or 0
  if n >= 1024 * 1024 then
    return string.format("%.1f MB", n / (1024 * 1024))
  end
  if n >= 1024 then
    return string.format("%.1f KB", n / 1024)
  end
  return tostring(math.floor(n)) .. " B"
end

local function log_rate(bytes, elapsed_ms)
  elapsed_ms = math.max(1, tonumber(elapsed_ms) or 1)
  local per_sec = (tonumber(bytes) or 0) / (elapsed_ms / 1000)
  if per_sec >= 1024 * 1024 then
    return string.format("%.2f MB/s", per_sec / (1024 * 1024))
  end
  if per_sec >= 1024 then
    return string.format("%.1f KB/s", per_sec / 1024)
  end
  return string.format("%.0f B/s", per_sec)
end

local function text_or(v, fallback)
  if v == nil then return fallback or "" end
  local s = tostring(v)
  if s == "" then return fallback or "" end
  return s
end

local function clamp(v, lo, hi)
  v = tonumber(v) or 0
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function web_bool(v)
  local s = tostring(v or ""):lower()
  return not (s == "" or s == "0" or s == "false" or s == "off" or s == "no")
end

local function eq_settings_path()
  return APP.APP_DIR .. "/" .. (APP.EQ_SETTINGS_FILE or "eq_settings.json")
end

local function eq_settings_snapshot()
  local out = {
    volume = APP.eq_settings.volume,
    hpf_freq = APP.eq_settings.hpf_freq,
    limiter_dbfs = APP.eq_settings.limiter_dbfs,
    limiter_peak = APP.eq_settings.limiter_peak,
    vbass = APP.eq_settings.vbass,
    vbass_low_hpf = APP.eq_settings.vbass_low_hpf,
    vbass_low_lpf = APP.eq_settings.vbass_low_lpf,
    vbass_out_hpf = APP.eq_settings.vbass_out_hpf,
    vbass_out_lpf = APP.eq_settings.vbass_out_lpf,
    vbass_drive = APP.eq_settings.vbass_drive,
    vbass_mix = APP.eq_settings.vbass_mix,
    vbass_even = APP.eq_settings.vbass_even,
    vbass_odd = APP.eq_settings.vbass_odd,
    vbass_solo = APP.eq_settings.vbass_solo,
    eq = {},
  }
  local eq = APP.eq_settings.eq or {}
  for i = 1, 7 do out.eq[i] = eq[i] or 0 end
  return out
end

local function merge_eq_settings(data)
  if type(data) ~= "table" then return false end
  local s = APP.eq_settings
  if data.volume ~= nil then s.volume = clamp(data.volume, 0, 1.2) end
  if data.hpf_freq ~= nil then s.hpf_freq = clamp(data.hpf_freq, 80, 260) end
  if data.limiter_peak ~= nil then
    s.limiter_peak = clamp(data.limiter_peak, 20000, 32767)
    s.limiter_dbfs = nil
  elseif data.limiter_dbfs ~= nil then
    s.limiter_dbfs = clamp(data.limiter_dbfs, -24, 0)
    s.limiter_peak = nil
  end
  if data.vbass ~= nil then s.vbass = web_bool(data.vbass) end
  if data.vbass_mix ~= nil then s.vbass_mix = clamp(data.vbass_mix, 0, 0.25) end
  if data.vbass_drive ~= nil then s.vbass_drive = clamp(data.vbass_drive, 0.1, 4) end
  if data.vbass_low_hpf ~= nil then s.vbass_low_hpf = clamp(data.vbass_low_hpf, 40, 220) end
  if data.vbass_low_lpf ~= nil then s.vbass_low_lpf = clamp(data.vbass_low_lpf, (s.vbass_low_hpf or 85) + 20, 260) end
  if data.vbass_out_hpf ~= nil then s.vbass_out_hpf = clamp(data.vbass_out_hpf, 120, 420) end
  if data.vbass_out_lpf ~= nil then s.vbass_out_lpf = clamp(data.vbass_out_lpf, (s.vbass_out_hpf or 180) + 80, 900) end
  if data.vbass_even ~= nil then s.vbass_even = clamp(data.vbass_even, 0, 2) end
  if data.vbass_odd ~= nil then s.vbass_odd = clamp(data.vbass_odd, 0, 2) end
  if data.vbass_solo ~= nil then s.vbass_solo = web_bool(data.vbass_solo) end
  if type(data.eq) == "table" then
    s.eq = s.eq or {}
    for i = 1, 7 do
      local v = data.eq[i] or data.eq[tostring(i)]
      if v ~= nil then s.eq[i] = clamp(v, -6, 6) end
    end
  end
  for i = 1, 7 do
    if s.eq[i] == nil then s.eq[i] = 0 end
  end
  return true
end

local function load_eq_settings()
  if not (file and file.getcontents and json and json.decode) then return false end
  local path = eq_settings_path()
  local read_ok, raw = pcall(function() return file.getcontents(path) end)
  if not read_ok then return false end
  if type(raw) ~= "string" or raw == "" then return false end
  local ok, data = pcall(json.decode, raw)
  if not ok then
    log("eq settings load failed:", tostring(data))
    return false
  end
  if merge_eq_settings(data) then
    log("eq settings loaded:", path)
    return true
  end
  return false
end

local function save_eq_settings_now()
  if not (file and file.open and json and json.encode) then return false end
  local path = eq_settings_path()
  local ok, body = pcall(json.encode, eq_settings_snapshot())
  if not ok or type(body) ~= "string" then
    log("eq settings encode failed:", tostring(body))
    return false
  end
  local fd = file.open(path, "w+")
  if not fd then
    log("eq settings open failed:", path)
    return false
  end
  local write_ok, err = pcall(function()
    if not fd:write(body) then error("write failed") end
    fd:write("\n")
    fd:flush()
  end)
  fd:close()
  if not write_ok then
    log("eq settings save failed:", tostring(err))
    return false
  end
  web_log("eq settings saved", path)
  return true
end

local function schedule_eq_settings_save()
  local old = APP.timers.eq_save
  if old then
    pcall(function() old:stop() end)
    pcall(function() old:unregister() end)
    APP.timers.eq_save = nil
  end
  if not (tmr and tmr.create) then
    save_eq_settings_now()
    return
  end
  local timer = tmr.create()
  APP.timers.eq_save = timer
  timer:alarm(APP.EQ_SAVE_DELAY_MS or 1000, tmr.ALARM_SINGLE or 0, function()
    if APP.timers.eq_save == timer then
      APP.timers.eq_save = nil
    end
    pcall(function() timer:unregister() end)
    save_eq_settings_now()
  end)
end

local WEB_HTML = [=[
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Music</title>
  <style>
    :root{color-scheme:light;--bg:#f8fafc;--panel:#fff;--text:#0f172a;--muted:#64748b;--soft:#f1f5f9;--line:#e2e8f0;--blue:#2563eb;--amber:#d97706;--red:#dc2626;--green:#15803d}
    *{box-sizing:border-box} body{margin:0;background:var(--bg);color:var(--text);font:14px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
    main{max-width:1060px;margin:0 auto;padding:24px 16px 40px}
    header{display:flex;align-items:flex-end;justify-content:space-between;gap:16px;margin-bottom:16px}
    h1{margin:0;font-size:28px;letter-spacing:0;font-weight:760}.sub{color:var(--muted);font-size:13px;margin-top:3px}
    .actions{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.btn{min-height:40px;border:1px solid var(--line);background:#fff;color:var(--text);border-radius:8px;padding:9px 13px;font-weight:650;cursor:pointer;transition:background .18s ease,border-color .18s ease,color .18s ease}.btn:hover{background:var(--soft)}.btn:focus-visible,.search:focus-visible,input[type=range]:focus-visible{outline:2px solid var(--blue);outline-offset:2px}.btn.primary{background:var(--blue);border-color:var(--blue);color:#fff}.btn.primary:hover{background:#1d4ed8}.btn.danger{color:var(--red)}.btn:disabled{opacity:.45;cursor:not-allowed}.homeBtn{display:inline-flex;align-items:center;text-decoration:none}
    .volumeBox{display:grid;grid-template-columns:auto 132px 44px;gap:8px;align-items:center;border:1px solid var(--line);border-radius:8px;background:#fff;padding:7px 10px;min-height:40px}.volumeBox label{font-weight:700}.volumeBox input{width:132px}.volumeBox span{font-variant-numeric:tabular-nums;color:var(--muted);text-align:right}
    .grid{display:grid;grid-template-columns:340px minmax(0,1fr);gap:14px}.panel{background:var(--panel);border:1px solid var(--line);border-radius:8px}
    .upload{padding:16px}.drop{border:1.5px dashed #cbd5e1;border-radius:8px;padding:26px 14px;text-align:center;background:#fbfdff}.drop.drag{border-color:var(--blue);background:#eff6ff}.drop strong{display:block;font-size:17px;margin-bottom:4px}.drop .sub{max-width:220px;margin:0 auto;color:#708094}
    input[type=file]{display:none}.queue{margin-top:14px;display:grid;gap:8px}.q{border:1px solid var(--line);border-radius:8px;padding:10px;background:#fff}.qtop{display:flex;justify-content:space-between;gap:8px}.bar{height:5px;background:#edf2f7;border-radius:99px;overflow:hidden;margin-top:8px}.bar div{height:100%;width:0;background:var(--amber)}
    .listHead{display:flex;align-items:center;justify-content:space-between;padding:14px;border-bottom:1px solid var(--line);gap:10px}.listHead h2{font-size:16px;margin:0;display:flex;align-items:center;gap:8px}
    .search{width:220px;max-width:100%;border:1px solid var(--line);border-radius:8px;padding:9px 10px;background:#fff;min-height:40px}
    table{width:100%;border-collapse:collapse}th,td{padding:12px 14px;border-bottom:1px solid #eef2f7;text-align:left;vertical-align:middle}th{font-size:12px;color:var(--muted);font-weight:750;background:#f8fafc}tbody tr:hover{background:#fbfdff}td.name{font-weight:650;word-break:break-all}.empty{padding:42px 14px;text-align:center;color:var(--muted)}
    .pill{display:inline-flex;border:1px solid var(--line);border-radius:999px;padding:2px 8px;font-size:12px;color:var(--muted);background:#fff}.status{margin-top:12px;color:var(--muted);min-height:20px}.status.err{color:var(--red)}.status.ok{color:var(--green)}
    .modal{position:fixed;inset:0;display:none;align-items:center;justify-content:center;padding:12px;background:rgba(15,23,42,.52);z-index:20}.modal.open{display:flex}.modalPanel{width:min(760px,100%);max-height:calc(100vh - 24px);overflow:auto;background:#fff;border-radius:10px;border:1px solid var(--line)}
    .eqHead{display:flex;align-items:center;justify-content:space-between;padding:15px 16px;border-bottom:1px solid var(--line)}.eqHead h2{margin:0;font-size:18px}.eqBody{padding:16px}.sliders{display:grid;grid-template-columns:repeat(7,1fr);gap:12px;align-items:end}.band{display:grid;justify-items:center;gap:8px}.band input{writing-mode:vertical-lr;direction:rtl;width:28px;height:170px}.band b{font-size:12px}.band span{font-variant-numeric:tabular-nums;color:var(--muted);font-size:12px}.eqRow{display:grid;grid-template-columns:120px 1fr 58px;gap:12px;align-items:center;margin-bottom:12px}.eqRow input{width:100%}.vbassBox{margin-top:18px;border-top:1px solid var(--line);padding-top:14px}.vbassHead{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:12px}.vbassHead strong{font-size:15px}.switch{display:flex;align-items:center;gap:8px;font-weight:700}.switch input{width:18px;height:18px}.vbassGrid{display:grid;grid-template-columns:1fr 1fr;gap:10px 16px}.vbassGrid .eqRow{grid-template-columns:86px 1fr 54px;margin:0}.eqFoot{display:flex;justify-content:space-between;gap:8px;padding:14px 16px;border-top:1px solid var(--line)}
    @media(max-width:760px){main{padding:16px 10px 28px}.grid{grid-template-columns:1fr}header{align-items:stretch;flex-direction:column}.actions{width:100%}.volumeBox{grid-template-columns:auto 1fr 44px;width:100%}.volumeBox input{width:100%}.listHead{align-items:stretch;flex-direction:column}.search{width:100%}th:nth-child(2),td:nth-child(2){display:none}.sliders{grid-template-columns:repeat(4,1fr)}.vbassGrid{grid-template-columns:1fr}}
    @media(prefers-reduced-motion:reduce){*{transition:none!important;scroll-behavior:auto!important}}
  </style>
</head>
<body>
<main>
  <header>
    <div><h1>Music</h1><div class="sub">管理 /sd/mp3 里的歌曲和歌词</div></div>
    <div class="actions"><a class="btn homeBtn" href="/main">返回主页</a><div class="volumeBox"><label>音量</label><input id="mainVolume" type="range" min="0" max="1.2" step="0.01"><span id="mainVolumeVal">0.60</span></div><button class="btn" id="refreshBtn">刷新</button><button class="btn primary" id="eqBtn">EQ</button></div>
  </header>
  <div class="grid">
    <section class="panel upload">
      <div class="drop" id="drop"><strong>上传歌曲</strong><div class="sub">支持 MP3 / WAV / LRC，可多选</div><button class="btn primary" id="pickBtn" style="margin-top:14px">选择文件</button><input id="fileInput" type="file" multiple accept=".mp3,.wav,.lrc,audio/mpeg,audio/wav"></div>
      <div class="queue" id="queue"></div>
      <div id="status" class="status">准备就绪</div>
    </section>
    <section class="panel">
      <div class="listHead"><h2>歌曲列表 <span class="pill" id="count">0</span></h2><input class="search" id="search" placeholder="搜索歌曲或歌词"></div>
      <div style="overflow:auto"><table><thead><tr><th>名称</th><th>大小</th><th>类型</th><th></th></tr></thead><tbody id="list"></tbody></table></div>
    </section>
  </div>
</main>
<div class="modal" id="eqDialog">
 <div class="modalPanel">
  <div class="eqHead"><h2>7 段 EQ</h2><button class="btn" id="closeEq">关闭</button></div>
  <div class="eqBody">
    <div class="eqRow"><label>高通 Hz</label><input id="hpf" type="range" min="80" max="260" step="5"><span id="hpfVal"></span></div>
    <div class="sliders" id="eqSliders"></div>
    <div class="vbassBox">
      <div class="vbassHead"><strong>虚拟低音</strong><label class="switch"><input id="vbass" type="checkbox">启用</label></div>
      <div class="vbassGrid">
        <div class="eqRow"><label>混合</label><input id="vbassMix" type="range" min="0" max="0.25" step="0.01"><span id="vbassMixVal"></span></div>
        <div class="eqRow"><label>驱动</label><input id="vbassDrive" type="range" min="0.8" max="4" step="0.1"><span id="vbassDriveVal"></span></div>
        <div class="eqRow"><label>提取高通</label><input id="vbassLowHpf" type="range" min="40" max="130" step="5"><span id="vbassLowHpfVal"></span></div>
        <div class="eqRow"><label>提取低通</label><input id="vbassLowLpf" type="range" min="130" max="260" step="5"><span id="vbassLowLpfVal"></span></div>
        <div class="eqRow"><label>输出高通</label><input id="vbassOutHpf" type="range" min="120" max="280" step="5"><span id="vbassOutHpfVal"></span></div>
        <div class="eqRow"><label>输出低通</label><input id="vbassOutLpf" type="range" min="420" max="900" step="10"><span id="vbassOutLpfVal"></span></div>
      </div>
    </div>
  </div>
  <div class="eqFoot"><button class="btn" id="resetEq">重置</button></div>
 </div>
</div>
<script>
const BASE="__APP_BASE__";
let apiBase=BASE+"/api";
const BANDS=[160,250,420,780,1250,2800,4300];
const EQ_DEFAULT={volume:.5,hpf_freq:120,limiter_dbfs:null,limiter_peak:31000,vbass:true,vbass_low_hpf:50,vbass_low_lpf:180,vbass_out_hpf:180,vbass_out_lpf:600,vbass_drive:3.5,vbass_mix:.25,vbass_even:1.9,vbass_odd:.5,vbass_solo:false,eq:[6.0,5.5,3.5,.3,-2.2,-.6,.8]};
let items=[], eq=JSON.parse(JSON.stringify(EQ_DEFAULT)), volumeTimer=0, eqTimer=0;
const $=id=>document.getElementById(id);
function apiUrl(base,path,params){const u=new URL(base+path,location.origin);Object.entries(params||{}).forEach(([k,v])=>u.searchParams.set(k,v));return u}
async function json(res){const t=await res.text();let d={};try{d=t?JSON.parse(t):{}}catch(e){throw new Error(res.redirected?"API 被重定向":(t&&t.trim().startsWith("<")?"API 返回了页面":(t||res.statusText)))}if(!res.ok||d.ok===false)throw new Error(d.error||res.statusText);return d}
async function request(path,options,params){const res=await fetch(apiUrl(apiBase,path,params),options||{});const data=await json(res);show("API "+apiBase,false);return data}
function esc(s){return String(s||"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c]))}
function bytes(n){n=Number(n)||0;if(n>=1048576)return(n/1048576).toFixed(1)+" MB";if(n>=1024)return Math.round(n/1024)+" KB";return n+" B"}
function show(s,err){$("status").textContent=s;$("status").className="status "+(err?"err":"ok")}
function typeOf(it){const e=(it.ext||"").toLowerCase();return e==="lrc"?"歌词":(e==="wav"?"WAV":"MP3")}
function render(){const q=$("search").value.trim().toLowerCase();const list=items.filter(x=>!q||String(x.name).toLowerCase().includes(q));$("count").textContent=list.length;const tb=$("list");tb.innerHTML="";if(!list.length){tb.innerHTML='<tr><td colspan="4" class="empty">没有文件</td></tr>';return}list.forEach(it=>{const tr=document.createElement("tr");tr.innerHTML=`<td class="name">${esc(it.name)}</td><td>${bytes(it.size)}</td><td><span class="pill">${typeOf(it)}</span></td><td style="text-align:right"><button class="btn danger">删除</button></td>`;tr.querySelector("button").onclick=()=>removeFile(it.name);tb.appendChild(tr)})}
async function load(){const d=await request("/list");items=d.items||[];render();show("已刷新",false)}
async function removeFile(name){if(!confirm("确认删除 "+name+" ?"))return;await request("/remove",{method:"DELETE"},{name});await load();show("已删除 "+name,false)}
function qitem(name){const el=document.createElement("div");el.className="q";el.innerHTML=`<div class="qtop"><strong>${esc(name)}</strong><span class="sub">等待</span></div><div class="bar"><div></div></div>`;$("queue").prepend(el);return{bar:el.querySelector(".bar div"),st:el.querySelector(".sub")}}
function uploadRaw(f,blob,offset,qi){return new Promise((resolve,reject)=>{const xhr=new XMLHttpRequest();xhr.open("PUT",apiUrl(apiBase,"/upload",{name:f.name,total:f.size,offset}));xhr.upload.onprogress=e=>{const loaded=offset+(e.lengthComputable?e.loaded:blob.size);qi.st.textContent=bytes(loaded)+" / "+bytes(f.size);qi.bar.style.width=(f.size?Math.round(loaded*100/f.size):100)+"%"};xhr.onload=()=>{let d={};try{d=xhr.responseText?JSON.parse(xhr.responseText):{}}catch(e){reject(new Error(xhr.responseText||xhr.statusText));return}if(xhr.status<200||xhr.status>=300||d.ok===false){reject(new Error(d.error||xhr.statusText));return}show("API "+apiBase,false);resolve(d)};xhr.onerror=()=>reject(new Error("上传失败"));xhr.send(blob)})}
async function uploadOne(f){const qi=qitem(f.name);let off=0;while(off<f.size||(f.size===0&&off===0)){const end=Math.min(off+__UPLOAD_CHUNK__,f.size);qi.st.textContent=bytes(off)+" / "+bytes(f.size);const d=await uploadRaw(f,f.slice(off,end),off,qi);off=Number(d.next_offset||end);if(f.size===0)break}qi.bar.style.width="100%";qi.st.textContent="完成"}
async function uploadFiles(fs){const arr=Array.from(fs||[]);for(const f of arr){try{await uploadOne(f)}catch(e){show(e.message,true)}}await load()}
function normEq(){eq=Object.assign(JSON.parse(JSON.stringify(EQ_DEFAULT)),eq||{});eq.eq=eq.eq||EQ_DEFAULT.eq.slice();return eq}
function fillMainVolume(){normEq();if(!$("mainVolume"))return;$("mainVolume").value=eq.volume;$("mainVolumeVal").textContent=Number(eq.volume||0).toFixed(2)}
function fillEq(){normEq();$("hpf").value=eq.hpf_freq;updateEqLabels();fillVbass();const box=$("eqSliders");box.innerHTML="";BANDS.forEach((f,i)=>{const v=Number(eq.eq[i]||0);const d=document.createElement("div");d.className="band";d.innerHTML=`<b>${f}</b><input type="range" min="-6" max="6" step="0.1" value="${v}" data-i="${i}"><span>${v.toFixed(1)}dB</span>`;d.querySelector("input").oninput=e=>{eq.eq[i]=Number(e.target.value);d.querySelector("span").textContent=eq.eq[i].toFixed(1)+"dB";scheduleEqSave()};box.appendChild(d)})}
function setVal(id,v){if($(id))$(id).value=v}
function setText(id,v,unit,d){if($(id))$(id).textContent=Number(v||0).toFixed(d||0)+(unit||"")}
function fillVbass(){setVal("vbassMix",eq.vbass_mix);setVal("vbassDrive",eq.vbass_drive);setVal("vbassLowHpf",eq.vbass_low_hpf);setVal("vbassLowLpf",eq.vbass_low_lpf);setVal("vbassOutHpf",eq.vbass_out_hpf);setVal("vbassOutLpf",eq.vbass_out_lpf);$("vbass").checked=!!eq.vbass;updateVbassLabels()}
function readVbass(){eq.vbass=$("vbass").checked;eq.vbass_mix=Number($("vbassMix").value);eq.vbass_drive=Number($("vbassDrive").value);eq.vbass_low_hpf=Number($("vbassLowHpf").value);eq.vbass_low_lpf=Number($("vbassLowLpf").value);eq.vbass_out_hpf=Number($("vbassOutHpf").value);eq.vbass_out_lpf=Number($("vbassOutLpf").value)}
function updateEqLabels(){$("hpfVal").textContent=$("hpf").value}
function updateVbassLabels(){setText("vbassMixVal",$("vbassMix").value,"",2);setText("vbassDriveVal",$("vbassDrive").value,"x",1);setText("vbassLowHpfVal",$("vbassLowHpf").value,"Hz",0);setText("vbassLowLpfVal",$("vbassLowLpf").value,"Hz",0);setText("vbassOutHpfVal",$("vbassOutHpf").value,"Hz",0);setText("vbassOutLpfVal",$("vbassOutLpf").value,"Hz",0)}
async function loadEq(){const d=await request("/eq");eq=d.eq||eq;normEq();fillMainVolume();fillEq()}
async function saveVolume(){eq.volume=Number($("mainVolume").value);fillMainVolume();await request("/eq",{method:"POST"},{volume:eq.volume});show("音量已更新",false)}
function scheduleVolumeSave(){eq.volume=Number($("mainVolume").value);fillMainVolume();clearTimeout(volumeTimer);volumeTimer=setTimeout(()=>saveVolume().catch(e=>show(e.message,true)),120)}
async function saveEq(){eq.hpf_freq=Number($("hpf").value);readVbass();const p={hpf_freq:eq.hpf_freq,limiter_peak:eq.limiter_peak||30000,vbass:eq.vbass?1:0,vbass_mix:eq.vbass_mix,vbass_drive:eq.vbass_drive,vbass_low_hpf:eq.vbass_low_hpf,vbass_low_lpf:eq.vbass_low_lpf,vbass_out_hpf:eq.vbass_out_hpf,vbass_out_lpf:eq.vbass_out_lpf,vbass_even:eq.vbass_even||1.2,vbass_odd:eq.vbass_odd||.8};eq.eq.forEach((v,i)=>p["eq"+(i+1)]=v);await request("/eq",{method:"POST"},p);show("EQ 已更新",false)}
function scheduleEqSave(){clearTimeout(eqTimer);eqTimer=setTimeout(()=>saveEq().catch(e=>show(e.message,true)),120)}
function openEq(){fillEq();$("eqDialog").classList.add("open")}
function closeEq(){$("eqDialog").classList.remove("open")}
$("refreshBtn").onclick=()=>load().catch(e=>show(e.message,true));$("search").oninput=render;$("mainVolume").oninput=scheduleVolumeSave;$("mainVolume").onchange=()=>saveVolume().catch(e=>show(e.message,true));$("pickBtn").onclick=()=>$("fileInput").click();$("fileInput").onchange=()=>{uploadFiles($("fileInput").files);$("fileInput").value=""};
["dragenter","dragover"].forEach(n=>$("drop").addEventListener(n,e=>{e.preventDefault();$("drop").classList.add("drag")}));["dragleave","drop"].forEach(n=>$("drop").addEventListener(n,e=>{e.preventDefault();$("drop").classList.remove("drag")}));$("drop").ondrop=e=>uploadFiles(e.dataTransfer.files);
$("eqBtn").onclick=()=>{openEq();loadEq().catch(e=>show(e.message,true))};$("closeEq").onclick=closeEq;$("eqDialog").onclick=e=>{if(e.target===$("eqDialog"))closeEq()};$("hpf").oninput=()=>{updateEqLabels();scheduleEqSave()};["vbassMix","vbassDrive","vbassLowHpf","vbassLowLpf","vbassOutHpf","vbassOutLpf"].forEach(id=>$(id).oninput=()=>{readVbass();updateVbassLabels();scheduleEqSave()});$("vbass").onchange=()=>{readVbass();scheduleEqSave()};$("resetEq").onclick=()=>{const volume=eq.volume;eq=JSON.parse(JSON.stringify(EQ_DEFAULT));eq.volume=volume;fillEq();saveEq().catch(e=>show(e.message,true))};
fillMainVolume();load().catch(e=>show(e.message,true));loadEq().catch(e=>show(e.message,true));
</script>
</body>
</html>
]=]

local WEB = {
  route_base = (app and app.route_base and app.route_base()) or "/mp3_player",
}
if WEB.route_base == "" then
  WEB.route_base = "/mp3_player"
end

local function web_url_decode(s)
  s = tostring(s or ""):gsub("+", " ")
  return (s:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function web_parse_query(query)
  local out = {}
  for pair in tostring(query or ""):gmatch("([^&]+)") do
    local key, value = pair:match("^([^=]*)=(.*)$")
    if not key then key, value = pair, "" end
    out[web_url_decode(key)] = web_url_decode(value)
  end
  return out
end

local function web_text(body, content_type, status)
  return {
    status = status or "200 OK",
    type = content_type or "text/plain; charset=utf-8",
    headers = { ["cache-control"] = "no-store" },
    body = body or "",
  }
end

local function web_json(data, status)
  data = data or {}
  local body = json and json.encode and json.encode(data) or "{}"
  return web_text(body, "application/json; charset=utf-8", status or "200 OK")
end

local function web_ok(data)
  data = data or {}
  data.ok = true
  return web_json(data)
end

local function web_err(status, msg)
  return web_json({ ok = false, error = tostring(msg or "request failed") }, status or "400 Bad Request")
end

local function web_ext(name)
  return tostring(name or ""):lower():match("%.([%w_%-]+)$") or ""
end

local function web_allowed_ext(ext)
  return ext == "mp3" or ext == "wav" or ext == "lrc"
end

local function web_safe_name(name)
  name = tostring(name or ""):gsub("\\", "/")
  name = name:match("([^/]+)$") or ""
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" or name == "." or name == ".." then
    return nil, "invalid file name"
  end
  local ext = web_ext(name)
  if not web_allowed_ext(ext) then
    return nil, "only mp3, wav and lrc are allowed"
  end
  return name
end

local function web_music_path(name)
  local safe, err = web_safe_name(name)
  if not safe then return nil, err end
  return APP.WEB_MUSIC_DIR .. "/" .. safe, safe
end

local function web_upload_temp_dir()
  return APP.WEB_MUSIC_DIR .. "/.uploading"
end

local function web_upload_temp_path(name)
  local safe, err = web_safe_name(name)
  if not safe then return nil, err end
  return web_upload_temp_dir() .. "/" .. safe .. ".tmp"
end

local function web_target_is_active_track(path, name)
  local track = APP.tracks and APP.tracks[APP.index]
  if not track then return false end
  if not (S.playing or S.opening or S.status == "PLAY" or S.status == "PAUSE") then
    return false
  end
  local target_path = tostring(path or "")
  local target_name = tostring(name or ""):lower()
  local track_path = tostring(track.path or "")
  local track_name = tostring(track.name or ""):lower()
  return (target_path ~= "" and track_path ~= "" and target_path == track_path) or
    (target_name ~= "" and track_name ~= "" and target_name == track_name)
end

local function web_ensure_music_dir()
  local st = file and file.stat and file.stat(APP.WEB_MUSIC_DIR)
  if st and st.is_dir then return true end
  return file and file.mkdir and file.mkdir(APP.WEB_MUSIC_DIR)
end

local function web_ensure_upload_dir()
  if not web_ensure_music_dir() then return false, "mkdir failed" end
  local dir = web_upload_temp_dir()
  local st = file and file.stat and file.stat(dir)
  if st and st.is_dir then return true end
  if st then
    file.remove(dir)
    if file.stat(dir) then return false, "upload temp path exists" end
  end
  if not (file and file.mkdir and file.mkdir(dir)) then
    return false, "upload temp mkdir failed"
  end
  return true
end

local function web_refresh_tracks(reason)
  reason = tostring(reason or "web")
  if S.playing or S.opening or S.in_tick or S.status == "PLAY" or S.status == "BUFFER" then
    APP.needs_rescan = true
    APP.rescan_reason = reason
    feature_log("Track list refresh deferred:", reason)
    return #APP.tracks
  end
  APP.tracks = scan_tracks()
  APP.needs_rescan = false
  APP.rescan_reason = nil
  feature_log("Track list refreshed:", reason, tostring(#APP.tracks) .. " tracks")
  return #APP.tracks
end

local function run_deferred_rescan(reason, force)
  if not APP.needs_rescan then return false end
  if not force and (S.playing or S.opening or S.in_tick) then return false end
  local was_opening = S.opening
  if force then S.opening = false end
  web_refresh_tracks(reason or APP.rescan_reason or "deferred")
  if force then S.opening = was_opening end
  return true
end

local function web_list(req)
  if not file or not file.listdir then
    return web_err("500 Internal Server Error", "file api missing")
  end
  web_ensure_music_dir()
  local list = file.listdir(APP.WEB_MUSIC_DIR) or {}
  local items = {}
  for _, entry in ipairs(list) do
    local name = tostring(entry.name or "")
    local ext = web_ext(name)
    if (not entry.is_dir) and web_allowed_ext(ext) then
      items[#items + 1] = {
        name = name,
        path = APP.WEB_MUSIC_DIR .. "/" .. name,
        size = tonumber(entry.size) or 0,
        ext = ext,
      }
    end
  end
  table.sort(items, function(a, b)
    return tostring(a.name):lower() < tostring(b.name):lower()
  end)
  return web_ok({ dir = APP.WEB_MUSIC_DIR, items = items })
end

local function web_remove(req)
  local q = web_parse_query(req and req.query)
  local path, safe_or_err = web_music_path(q.name or "")
  if not path then return web_err("400 Bad Request", safe_or_err) end
  local st = file.stat(path)
  if not st or st.is_dir then return web_err("404 Not Found", "file not found") end
  file.remove(path)
  if file.stat(path) then return web_err("500 Internal Server Error", "remove failed") end
  web_refresh_tracks("remove")
  return web_ok({ name = safe_or_err })
end

local function web_open_upload_temp(path, offset)
  local fd
  if offset == 0 then
    if file.stat(path) then
      file.remove(path)
    end
    fd = file.open(path, "w+")
  else
    local st = file.stat(path)
    if not st or st.is_dir or (st.size or 0) ~= offset then
      return nil, "upload offset mismatch"
    end
    fd = file.open(path, "a+")
  end
  if not fd then return nil, "open failed" end
  return fd
end

local function web_upload_yield()
  if APP.audio and APP.audio.yield then
    local ok = pcall(APP.audio.yield)
    if ok then return end
  end
  if tmr and tmr.wdclr then
    pcall(tmr.wdclr)
  end
end

local function web_prefetch_before_upload()
  if not (S.playing and APP.audio and APP.audio.prefetch) then return end
  local target = tonumber(APP.MP3_PREFETCH_UPLOAD_TARGET_BYTES) or (2 * 1024 * 1024)
  local max_bytes = tonumber(APP.MP3_PREFETCH_UPLOAD_READ_BYTES) or target
  local ok, cached, cap, eof = pcall(APP.audio.prefetch, target, max_bytes)
  if ok then
    feature_log(
      "Upload prefetch:",
      tostring(cached or 0) .. "/" .. tostring(cap or 0),
      eof and "eof" or ""
    )
  else
    web_log("upload prefetch failed", tostring(cached))
  end
end

local function web_write_upload_body(req, fd, offset, total, progress_cb)
  local written = 0
  local since_yield = 0
  local write_limit = math.max(1024, tonumber(APP.WEB_UPLOAD_WRITE_BYTES) or (16 * 1024))
  local yield_limit = math.max(write_limit, tonumber(APP.WEB_UPLOAD_YIELD_BYTES) or (64 * 1024))
  while true do
    local chunk = req.getbody()
    if not chunk then break end
    local n = #chunk
    if n > 0 then
      if offset + written + n > total then
        return nil, "body exceeds total"
      end
      local pos = 1
      while pos <= n do
        local take = math.min(write_limit, n - pos + 1)
        local piece = (pos == 1 and take == n) and chunk or chunk:sub(pos, pos + take - 1)
        local before = written
        if not fd:write(piece) then
          return nil, "write failed"
        end
        written = written + take
        since_yield = since_yield + take
        if progress_cb then
          progress_cb(offset + before, offset + written)
        end
        pos = pos + take
        if since_yield >= yield_limit then
          since_yield = 0
          web_upload_yield()
        end
      end
    end
  end
  if fd.flush then fd:flush() end
  return written
end

local function web_finish_upload(tmp_path, final_path, total)
  if not file.rename then
    return false, "rename missing"
  end
  total = math.floor(tonumber(total) or -1)
  local tmp_st = file.stat(tmp_path)
  if not tmp_st or tmp_st.is_dir then
    return false, "temp file missing"
  end
  if total < 0 or (tmp_st.size or 0) ~= total then
    return false, "temp size mismatch"
  end
  local st = file.stat(final_path)
  if st and st.is_dir then
    return false, "target is directory"
  end
  if st then
    file.remove(final_path)
    if file.stat(final_path) then
      return false, "replace failed"
    end
  end
  if not file.rename(tmp_path, final_path) then
    return false, "rename failed"
  end
  local final_st = file.stat(final_path)
  if not final_st or final_st.is_dir or (final_st.size or 0) ~= total then
    return false, "final size mismatch"
  end
  return true
end

local function web_upload_log_progress(name, offset, next_offset, total)
  name = tostring(name or "")
  total = tonumber(total) or 0
  offset = tonumber(offset) or 0
  next_offset = tonumber(next_offset) or offset
  local key = name ~= "" and name or "upload"
  local state = APP.upload_logs[key]
  local now = log_now_ms()

  if offset == 0 or not state then
    state = {
      start_ms = now,
      next_pct = 10,
      total = total,
    }
    APP.upload_logs[key] = state
    feature_log("Upload started:", name, "(" .. log_bytes(total) .. ")")
  end

  if total <= 0 then
    feature_log("Upload complete:", name, "0 B in 0.0s, avg 0 B/s")
    APP.upload_logs[key] = nil
    return
  end

  local pct = math.floor(next_offset * 100 / total)
  local next_pct = tonumber(state.next_pct) or 10
  while pct >= next_pct and next_pct < 100 do
    feature_log("Upload progress:", name, tostring(next_pct) .. "%")
    next_pct = next_pct + 10
  end
  state.next_pct = next_pct

  if next_offset >= total then
    local elapsed = math.max(1, now - (tonumber(state.start_ms) or now))
    feature_log(
      "Upload complete:",
      name,
      log_bytes(total) .. " in " .. string.format("%.1fs", elapsed / 1000),
      "avg " .. log_rate(total, elapsed)
    )
    APP.upload_logs[key] = nil
  end
end

local function web_upload(req)
  local q = web_parse_query(req and req.query)
  local path, safe_or_err = web_music_path(q.name or "")
  if not path then return web_err("400 Bad Request", safe_or_err) end
  local tmp_path, tmp_err = web_upload_temp_path(safe_or_err)
  if not tmp_path then return web_err("400 Bad Request", tmp_err) end
  local offset = math.floor(tonumber(q.offset) or 0)
  local total = math.floor(tonumber(q.total) or -1)
  if offset < 0 or total < 0 or offset > total then return web_err("400 Bad Request", "invalid offset") end
  if total > APP.WEB_MAX_FILE_SIZE then return web_err("413 Payload Too Large", "file too large") end
  local dir_ok, dir_err = web_ensure_upload_dir()
  if not dir_ok then return web_err("500 Internal Server Error", dir_err) end

  if web_target_is_active_track(path, safe_or_err) then
    return web_err("409 Conflict", "target is active track")
  end

  if offset == 0 then
    web_prefetch_before_upload()
  end

  local fd, open_err = web_open_upload_temp(tmp_path, offset)
  if not fd then return web_err(open_err == "upload offset mismatch" and "409 Conflict" or "500 Internal Server Error", open_err) end

  local written, write_err = web_write_upload_body(req, fd, offset, total, function(chunk_offset, chunk_next)
    web_upload_log_progress(safe_or_err, chunk_offset, chunk_next, total)
  end)
  fd:close()
  if not written then return web_err("400 Bad Request", write_err) end
  local next_offset = offset + written
  if written == 0 then
    web_upload_log_progress(safe_or_err, offset, next_offset, total)
  end
  if next_offset >= total then
    local finish_ok, finish_err = web_finish_upload(tmp_path, path, total)
    if not finish_ok then return web_err("500 Internal Server Error", finish_err) end
    web_refresh_tracks("upload")
  end
  return web_ok({
    name = safe_or_err,
    temp_path = tmp_path,
    path = path,
    next_offset = next_offset,
    total = total,
    done = next_offset >= total,
    tracks = APP.tracks and #APP.tracks or 0,
  })
end

local function web_eq_table()
  return eq_settings_snapshot()
end

local function web_eq(req)
  local q = web_parse_query(req and req.query)
  local changed = false
  web_log("web_eq enter", "method=" .. tostring(req and req.method), "query=" .. tostring(req and req.query or ""))
  if q.volume ~= nil then
    APP.eq_settings.volume = clamp(q.volume, 0, 1.2)
    changed = true
  end
  if q.hpf_freq ~= nil then
    APP.eq_settings.hpf_freq = clamp(q.hpf_freq, 80, 260)
    changed = true
  end
  if q.limiter_peak ~= nil then
    APP.eq_settings.limiter_peak = clamp(q.limiter_peak, 20000, 32767)
    APP.eq_settings.limiter_dbfs = nil
    changed = true
  end
  if q.limiter_dbfs ~= nil then
    APP.eq_settings.limiter_dbfs = clamp(q.limiter_dbfs, -24, 0)
    APP.eq_settings.limiter_peak = nil
    changed = true
  end
  if q.vbass ~= nil then
    APP.eq_settings.vbass = web_bool(q.vbass)
    changed = true
  end
  if q.vbass_mix ~= nil then
    APP.eq_settings.vbass_mix = clamp(q.vbass_mix, 0, 0.25)
    changed = true
  end
  if q.vbass_drive ~= nil then
    APP.eq_settings.vbass_drive = clamp(q.vbass_drive, 0.1, 4)
    changed = true
  end
  if q.vbass_low_hpf ~= nil then
    APP.eq_settings.vbass_low_hpf = clamp(q.vbass_low_hpf, 40, 220)
    changed = true
  end
  if q.vbass_low_lpf ~= nil then
    APP.eq_settings.vbass_low_lpf = clamp(q.vbass_low_lpf, (APP.eq_settings.vbass_low_hpf or 85) + 20, 260)
    changed = true
  end
  if q.vbass_out_hpf ~= nil then
    APP.eq_settings.vbass_out_hpf = clamp(q.vbass_out_hpf, 120, 420)
    changed = true
  end
  if q.vbass_out_lpf ~= nil then
    APP.eq_settings.vbass_out_lpf = clamp(q.vbass_out_lpf, (APP.eq_settings.vbass_out_hpf or 180) + 80, 900)
    changed = true
  end
  if q.vbass_even ~= nil then
    APP.eq_settings.vbass_even = clamp(q.vbass_even, 0, 2)
    changed = true
  end
  if q.vbass_odd ~= nil then
    APP.eq_settings.vbass_odd = clamp(q.vbass_odd, 0, 2)
    changed = true
  end
  if q.vbass_solo ~= nil then
    APP.eq_settings.vbass_solo = web_bool(q.vbass_solo)
    changed = true
  end
  for i = 1, 7 do
    local key = "eq" .. i
    if q[key] ~= nil then
      APP.eq_settings.eq[i] = clamp(q[key], -6, 6)
      changed = true
    end
  end
  if changed then
    for i = 1, 7 do
      if APP.eq_settings.eq[i] == nil then
        APP.eq_settings.eq[i] = 0
      end
    end
    apply_audio_effects()
    schedule_eq_settings_save()
    web_log("web_eq apply",
      "volume=" .. tostring(APP.eq_settings.volume),
      "hpf=" .. tostring(APP.eq_settings.hpf_freq),
      "vbass=" .. tostring(APP.eq_settings.vbass),
      "vbass_mix=" .. tostring(APP.eq_settings.vbass_mix),
      "limiter=" .. tostring(APP.eq_settings.limiter_peak or APP.eq_settings.limiter_dbfs))
  end
  return web_ok({ eq = web_eq_table() })
end

local function web_stats(req)
  if not APP.audio or not APP.audio.stats then
    return web_ok({ loaded = false })
  end
  local ok, st = pcall(function()
    return APP.audio.stats()
  end)
  if not ok then
    return web_err("500 Internal Server Error", tostring(st))
  end
  return web_ok({ loaded = true, stats = st })
end

local function web_index(req)
  local html = WEB_HTML:gsub("__APP_BASE__", WEB.route_base)
  html = html:gsub("__UPLOAD_CHUNK__", tostring(APP.WEB_CHUNK_SIZE or (16 * 1024)))
  return web_text(html, "text/html; charset=utf-8", "200 OK")
end

local function web_favicon(req)
  return web_text("", "image/x-icon", "204 No Content")
end

local function web_request_path(req)
  local uri = tostring(req and req.uri or "")
  return uri:match("^([^?]*)") or uri
end

local function web_api_dispatch(req)
  local path = web_request_path(req)
  local endpoint = path:match("/api/([^/]+)$") or ""
  local method = req and req.method
  web_log("api", "path=" .. tostring(path), "endpoint=" .. tostring(endpoint), "method=" .. tostring(method))

  if endpoint == "list" and method == httpd.GET then
    return web_list(req)
  end
  if endpoint == "upload" and method == httpd.PUT then
    return web_upload(req)
  end
  if endpoint == "remove" and method == httpd.DELETE then
    return web_remove(req)
  end
  if endpoint == "eq" and (method == httpd.GET or method == httpd.POST) then
    return web_eq(req)
  end
  if endpoint == "stats" and method == httpd.GET then
    return web_stats(req)
  end
  if endpoint == "state" and method == httpd.GET and web_state then
    return web_state(req)
  end
  return web_err("404 Not Found", "api not found")
end

local function register_web_route(method, route, handler)
  if not httpd or not httpd.dynamic then return false end
  local ok, err = pcall(function()
    local e = httpd.dynamic(method, route, handler)
    if e then error(e) end
  end)
  if not ok then
    log("web route failed", "method=" .. tostring(method), route, err)
    return false
  end
  web_log("route", "method=" .. tostring(method), route)
  return true
end

local function register_web_routes_for_base(base)
  if not base or base == "" then return end
  local api_prefix = base .. "/api"
  register_web_route(httpd.GET, base .. "/", web_index)
  register_web_route(httpd.GET, api_prefix .. "/*", web_api_dispatch)
  register_web_route(httpd.PUT, api_prefix .. "/*", web_api_dispatch)
  register_web_route(httpd.DELETE, api_prefix .. "/*", web_api_dispatch)
  register_web_route(httpd.POST, api_prefix .. "/*", web_api_dispatch)
end

local function start_web()
  if not httpd or not httpd.start then return end
  pcall(httpd.stop)
  local ok, err = pcall(function()
    httpd.start({
      webroot = "/sd",
      auto_index = httpd.INDEX_NONE,
      max_handlers = APP.WEB_MAX_HANDLERS,
    })
  end)
  if not ok then
    log("web start failed", err)
  else
    web_log("start", "base=" .. tostring(WEB.route_base), "max_handlers=" .. tostring(APP.WEB_MAX_HANDLERS))
  end
  register_web_routes_for_base(WEB.route_base)
  APP.web_started = true
end

local function now_ms()
  if millis then
    local ok, value = pcall(millis)
    if ok and value then return tonumber(value) or 0 end
  end
  if tmr and tmr.now then
    local ok, value = pcall(tmr.now)
    if ok and value then return math.floor((tonumber(value) or 0) / 1000) end
  end
  if tmr and tmr.time then
    local ok, value = pcall(tmr.time)
    if ok and value then return (tonumber(value) or 0) * 1000 end
  end
  return 0
end

local profile_clock_fn = nil

local function profile_now_us()
  if not profile_clock_fn then
    if tmr and tmr.now then
      profile_clock_fn = function()
        return tonumber(tmr.now()) or 0
      end
    elseif millis then
      profile_clock_fn = function()
        return (tonumber(millis()) or 0) * 1000
      end
    else
      profile_clock_fn = function()
        return now_ms() * 1000
      end
    end
  end
  return profile_clock_fn()
end

local function profile_elapsed_us(start_us)
  local now = profile_now_us()
  if now >= (tonumber(start_us) or 0) then
    return now - (tonumber(start_us) or 0)
  end
  return 0
end

local function reset_profile()
  APP.prof = { last_log_us = profile_now_us() }
end

local function prof_bucket(name)
  if not APP.prof then reset_profile() end
  local bucket = APP.prof[name]
  if not bucket then
    bucket = { calls = 0, us = 0, max_us = 0, bytes = 0 }
    APP.prof[name] = bucket
  end
  return bucket
end

local function prof_add(name, us, bytes)
  if not APP.PROFILE_AUDIO then return end
  local bucket = prof_bucket(name)
  us = tonumber(us) or 0
  bucket.calls = bucket.calls + 1
  bucket.us = bucket.us + us
  bucket.bytes = bucket.bytes + (tonumber(bytes) or 0)
  if us > bucket.max_us then
    bucket.max_us = us
  end
end

local function prof_fmt(label, bucket)
  local calls = tonumber(bucket and bucket.calls) or 0
  if calls <= 0 then
    return label .. "=-"
  end
  local avg = math.floor((tonumber(bucket.us) or 0) / calls)
  local max_us = math.floor(tonumber(bucket.max_us) or 0)
  local bytes = math.floor((tonumber(bucket.bytes) or 0) / 1024)
  local suffix = bytes > 0 and ("," .. bytes .. "KB") or ""
  return label .. "=" .. avg .. "/" .. max_us .. "us" .. suffix
end

local function module_prof_fmt(st, label, prefix)
  local calls = tonumber(st and st[prefix .. "_calls"]) or 0
  if calls <= 0 then
    return label .. "=-"
  end
  local avg = math.floor(tonumber(st[prefix .. "_avg_us"]) or 0)
  local max_us = math.floor(tonumber(st[prefix .. "_max_us"]) or 0)
  local bytes = math.floor((tonumber(st[prefix .. "_bytes"]) or 0) / 1024)
  local suffix = bytes > 0 and ("," .. bytes .. "KB") or ""
  return label .. "=" .. avg .. "/" .. max_us .. "us" .. suffix
end

local function reset_audio_stats()
  if APP.audio and APP.audio.reset_stats then
    pcall(function() APP.audio.reset_stats() end)
  end
end

local function prefetch_audio(target_bytes, max_bytes)
  if not APP.audio or not APP.audio.prefetch then return end
  pcall(function()
    APP.audio.prefetch(
      target_bytes or APP.MP3_PREFETCH_TARGET_BYTES,
      max_bytes or APP.MP3_PREFETCH_READ_BYTES
    )
  end)
end

local function log_audio_stats()
  if not APP.audio or not APP.audio.stats then return end
  local ok, st = pcall(function()
    return APP.audio.stats()
  end)
  if ok and type(st) == "table" then
    log(
      "audio.prof",
      module_prof_fmt(st, "read", "read"),
      module_prof_fmt(st, "file", "file"),
      module_prof_fmt(st, "sync", "sync"),
      module_prof_fmt(st, "decode", "decode"),
      module_prof_fmt(st, "info", "info"),
      module_prof_fmt(st, "pcm", "pcm"),
      module_prof_fmt(st, "copy", "copy"),
      module_prof_fmt(st, "dsp", "dsp"),
      module_prof_fmt(st, "pushlua", "push"),
      module_prof_fmt(st, "alloc", "alloc"),
      "prefetch=" .. tostring(st.prefetch_bytes or 0) .. "/" .. tostring(st.prefetch_buffer_bytes or 0),
      "pcmb=" .. tostring(st.pcm_buffer_bytes or 0) .. "/" .. tostring(st.pcm_buffer_capacity or 0),
      "i2sp=" .. tostring(st.i2s_pending_bytes or 0),
      "short=" .. tostring(st.i2s_short_writes or 0),
      "task=" .. tostring(st.i2s_task_running or 0) ..
        "/" .. tostring(st.i2s_task_eof or 0) ..
        "/" .. tostring(st.i2s_task_error or 0) ..
        "/" .. tostring(st.i2s_task_buffering or 0) ..
        "/" .. tostring(st.i2s_task_paused or 0) ..
        "," .. tostring(math.floor((tonumber(st.i2s_task_written_bytes) or 0) / 1024)) .. "KB",
      "prod=" .. tostring(st.i2s_producer_running or 0) ..
        "/" .. tostring(st.i2s_producer_eof or 0) ..
        "/" .. tostring(st.i2s_producer_error or 0) ..
        "," .. tostring(math.floor((tonumber(st.i2s_producer_decoded_bytes) or 0) / 1024)) .. "KB"
    )
  end
  reset_audio_stats()
end

local function maybe_log_profile()
  if not APP.PROFILE_AUDIO then return end
  if not APP.prof then reset_profile() end
  local now = profile_now_us()
  local last = tonumber(APP.prof.last_log_us) or now
  if now < last or now - last < APP.PROFILE_LOG_MS * 1000 then
    return
  end

  log(
    "lua.prof",
    prof_fmt("tick", APP.prof.play_tick),
    prof_fmt("read", APP.prof.audio_read),
    prof_fmt("fill", APP.prof.buffer_fill),
    prof_fmt("i2s", APP.prof.i2s_write),
    prof_fmt("ui", APP.prof.ui)
  )
  log_audio_stats()
  reset_profile()
end

local function reset_play_clock()
  S.clock_base_ms = 0
  S.clock_start_ms = now_ms()
end

local function current_play_clock_ms()
  local elapsed = tonumber(S.clock_base_ms) or 0
  if S.playing and not S.buffering then
    elapsed = elapsed + math.max(0, now_ms() - (tonumber(S.clock_start_ms) or now_ms()))
  end
  local dur = tonumber(S.duration_ms) or 0
  if dur > 0 then
    elapsed = clamp(elapsed, 0, dur)
  end
  return math.floor(elapsed)
end

local function bytes_to_ms(bytes, bytes_per_sec)
  bytes = tonumber(bytes) or 0
  bytes_per_sec = tonumber(bytes_per_sec) or 0
  if bytes <= 0 or bytes_per_sec <= 0 then
    return 0
  end
  return math.floor(bytes / (bytes_per_sec / 1000))
end

local function bitrate_duration_ms(file_size, bitrate)
  file_size = tonumber(file_size) or 0
  bitrate = tonumber(bitrate) or 0
  if file_size <= 0 or bitrate <= 0 then
    return 0
  end
  return math.floor(file_size / (bitrate / 8000))
end

local function pcm_play_clock_ms()
  local bytes = tonumber(S.pcm_bytes) or 0
  local bps = tonumber(S.bytes_per_sec) or 0
  if bytes <= 0 or bps <= 0 then
    return 0
  end
  local elapsed = bytes_to_ms(bytes, bps)
  local dur = tonumber(S.duration_ms) or 0
  if dur > 0 then
    elapsed = clamp(elapsed, 0, dur)
  end
  return elapsed
end

local function play_position_ms()
  local clock_ms = current_play_clock_ms()
  local pcm_ms = pcm_play_clock_ms()
  if pcm_ms > 0 then
    return math.max(clock_ms, pcm_ms)
  end
  return clock_ms
end

web_state = function(_req)
  local task_state = nil
  if APP.audio and APP.audio.i2s_play_state then
    local ok, st = pcall(function() return APP.audio.i2s_play_state() end)
    if ok and type(st) == "table" then
      task_state = st
    end
  end
  return web_ok({
    playing = S.playing and true or false,
    status = S.status,
    elapsed_ms = play_position_ms(),
    clock_ms = current_play_clock_ms(),
    pcm_ms = pcm_play_clock_ms(),
    duration_ms = tonumber(S.duration_ms) or 0,
    duration_estimated = S.duration_estimated and true or false,
    pcm_bytes = tonumber(S.pcm_bytes) or 0,
    bytes_per_sec = tonumber(S.bytes_per_sec) or 0,
    file_size = tonumber(S.file_size) or 0,
    bitrate = tonumber(S.bitrate) or 0,
    track = APP.tracks[APP.index],
    i2s = task_state,
  })
end

local function pause_play_clock()
  S.clock_base_ms = play_position_ms()
  S.clock_start_ms = now_ms()
end

local function resume_play_clock()
  S.clock_start_ms = now_ms()
end

local function sd_to_lv(path)
  if type(path) == "string" and path:sub(1, 4) == "/sd/" then
    return "S:/" .. path:sub(5)
  end
  return path
end

local function asset(name)
  return sd_to_lv(APP.ASSET_DIR .. "/" .. name)
end

local function stop_timer(timer)
  if not timer then return end
  pcall(function() timer:stop() end)
  pcall(function() timer:unregister() end)
end

local function is_audio_name(name)
  local ext = tostring(name or ""):match("%.([%a%d]+)$")
  if not ext then return false end
  ext = ext:lower()
  return ext == "mp3" or ext == "wav"
end

local function track_title(name)
  name = tostring(name or "")
  name = name:gsub("%.[%a%d]+$", "")
  return name ~= "" and name or "Untitled"
end

local function entry_path(dir, entry)
  if entry and entry.path and entry.path ~= "" then return entry.path end
  return dir .. "/" .. tostring(entry and entry.name or "")
end

local function log_scan_result(tracks)
  tracks = tracks or {}
  local names = {}
  local max_names = 12
  for i = 1, math.min(#tracks, max_names) do
    names[#names + 1] = tostring(tracks[i].name or tracks[i].title or "")
  end
  local suffix = #tracks > max_names and (" ... +" .. tostring(#tracks - max_names) .. " more") or ""
  local list = #names > 0 and table.concat(names, ", ") or "none"
  feature_log("Scan found " .. tostring(#tracks) .. " tracks:", list .. suffix)
end

scan_tracks = function()
  local found = {}
  if not file or not file.listdir then
    feature_log("Scan skipped: file.listdir unavailable")
    return found
  end

  for _, dir in ipairs(APP.MUSIC_DIRS) do
    local ok, entries = pcall(function()
      return file.listdir(dir)
    end)
    if ok and type(entries) == "table" then
      for _, e in ipairs(entries) do
        if e and (not e.is_dir) and e.name and is_audio_name(e.name) then
          found[#found + 1] = {
            name = tostring(e.name),
            title = track_title(e.name),
            path = entry_path(dir, e),
            dir = dir,
            size = tonumber(e.size) or tonumber(e.file_size) or 0,
          }
        end
      end
    end
  end

  table.sort(found, function(a, b)
    return tostring(a.name):lower() < tostring(b.name):lower()
  end)
  log_scan_result(found)
  return found
end

local function find_sidecar(path, ext)
  if not path or not ext or not file or not file.listdir then return nil end
  local dir, name = path:match("^(.*)/([^/]+)$")
  if not dir or not name then return nil end
  local base = name:gsub("%.[^%.]+$", "")
  local want = (base .. ext):lower()
  local ok, entries = pcall(function()
    return file.listdir(dir)
  end)
  if ok and type(entries) == "table" then
    for _, e in ipairs(entries) do
      if e and (not e.is_dir) and e.name and tostring(e.name):lower() == want then
        return entry_path(dir, e)
      end
    end
  end
  local direct = dir .. "/" .. base .. ext
  if file.exists and file.exists(direct) then return direct end
  return nil
end

local function parse_time_tag(mm, ss, frac)
  local ms = (tonumber(mm) or 0) * 60000 + (tonumber(ss) or 0) * 1000
  frac = tostring(frac or "")
  if #frac == 1 then
    ms = ms + tonumber(frac) * 100
  elseif #frac >= 2 then
    ms = ms + tonumber(frac:sub(1, 2)) * 10
  end
  return ms
end

local function lyric_utf8_chars(text)
  local chars = {}
  local s = text_or(text, "")
  local i = 1
  local len = #s
  while i <= len do
    local b = s:byte(i) or 0
    local n = 1
    if b >= 0xF0 then
      n = 4
    elseif b >= 0xE0 then
      n = 3
    elseif b >= 0xC0 then
      n = 2
    end
    if i + n - 1 > len then n = 1 end
    chars[#chars + 1] = s:sub(i, i + n - 1)
    i = i + n
  end
  return chars
end

local function lyric_chars_join(chars, first, last)
  local out = {}
  first = math.max(1, first or 1)
  last = math.min(#chars, last or #chars)
  for i = first, last do
    out[#out + 1] = chars[i]
  end
  return table.concat(out):gsub("^%s+", ""):gsub("%s+$", "")
end

local function lyric_target_split(total, limit)
  if total <= 0 then return 0 end
  local min_first = math.floor(limit * 2 / 3)
  local split
  if total <= math.floor(limit * 4 / 3) then
    split = math.floor(total * 0.62 + 0.5)
  else
    split = math.floor((total + 1) / 2)
  end
  split = math.max(min_first, split)
  split = math.max(total - limit, split)
  split = math.min(limit, split)
  return split
end

local function wrap_lyric_text(text)
  local limit = tonumber(APP.LYRIC_WRAP_LIMIT) or 15
  local chars = lyric_utf8_chars(text)
  local total = #chars
  if total <= limit then
    return text_or(text, "")
  end

  total = math.min(total, limit * 2)
  local target = lyric_target_split(total, limit)
  local best
  local best_score
  for i = 2, total - 1 do
    local ch = chars[i]
    if ch == " " or ch == "\t" then
      local left = i - 1
      local right = total - i
      if left > 0 and right > 0 and left <= limit and right <= limit then
        local score = math.abs(left - target)
        if not best_score or score < best_score then
          best = i
          best_score = score
        end
      end
    end
  end

  if best then
    local first = lyric_chars_join(chars, 1, best - 1)
    local second = lyric_chars_join(chars, best + 1, total)
    if first ~= "" and second ~= "" then
      return first .. "\n" .. second
    end
  end

  local split = lyric_target_split(total, limit)
  local first = lyric_chars_join(chars, 1, split)
  local second = lyric_chars_join(chars, split + 1, total)
  if first == "" or second == "" then
    return lyric_chars_join(chars, 1, total)
  end
  return first .. "\n" .. second
end

local function load_lyrics(track)
  S.lyrics = {}
  S.lyric_idx = 1
  local path = find_sidecar(track and track.path, ".lrc")
  if not path or not file or not file.getcontents then return end
  local raw = file.getcontents(path)
  if type(raw) ~= "string" or raw == "" then return end

  for line in raw:gmatch("[^\r\n]+") do
    local clean = line:gsub("%[[^%]]+%]", "")
    clean = clean:gsub("^%s+", ""):gsub("%s+$", "")
    for mm, ss, frac in line:gmatch("%[(%d+):(%d+)%.?(%d*)%]") do
      if clean ~= "" then
        S.lyrics[#S.lyrics + 1] = {
          ms = parse_time_tag(mm, ss, frac),
          text = wrap_lyric_text(clean),
        }
      end
    end
  end

  table.sort(S.lyrics, function(a, b)
    return (a.ms or 0) < (b.ms or 0)
  end)
end

local function lyric_text_at(ms)
  local lines = S.lyrics
  if not lines or #lines == 0 then return "", "" end
  if S.lyric_idx < 1 then S.lyric_idx = 1 end
  while S.lyric_idx < #lines and ms >= (lines[S.lyric_idx + 1].ms or 0) do
    S.lyric_idx = S.lyric_idx + 1
  end
  while S.lyric_idx > 1 and ms < (lines[S.lyric_idx].ms or 0) do
    S.lyric_idx = S.lyric_idx - 1
  end
  local cur = lines[S.lyric_idx] and lines[S.lyric_idx].text or ""
  local next_line = lines[S.lyric_idx + 1] and lines[S.lyric_idx + 1].text or ""
  return cur, next_line
end

local function lyric_scroll_px(ms, distance)
  local lines = S.lyrics
  if not lines or #lines == 0 then return 0 end
  local cur = lines[S.lyric_idx]
  local next_line = lines[S.lyric_idx + 1]
  if not cur or not next_line then return 0 end
  local cur_ms = tonumber(cur.ms) or 0
  local next_ms = tonumber(next_line.ms) or cur_ms
  if next_ms <= cur_ms then return 0 end
  local px = tonumber(distance) or (LYRIC_ACTIVE_LINE_H + LYRIC_LINE_SPACE)
  return math.floor(clamp((ms - cur_ms) / (next_ms - cur_ms), 0, 1) * px)
end

local function start_i2s(rate, channels)
  local profiles = APP.I2S_BUFFER_FALLBACKS or {
    { count = APP.BUFFER_COUNT, len = APP.BUFFER_LEN },
  }
  local last_err = nil
  if APP.audio and APP.audio.i2s_start then
    for _, profile in ipairs(profiles) do
      local ok, started_or_err, start_err = pcall(APP.audio.i2s_start, {
        port = APP.I2S_ID,
        sample_rate = rate,
        channels = channels,
        bits = APP.I2S_BITS,
        buffer_count = profile.count or APP.BUFFER_COUNT,
        buffer_len = profile.len or APP.BUFFER_LEN,
        data_out_pin = APP.DATA_OUT_PIN,
      })
      if ok and started_or_err then
        if profile.count ~= APP.BUFFER_COUNT or profile.len ~= APP.BUFFER_LEN then
          log("i2s dma fallback", tostring(profile.count) .. "x" .. tostring(profile.len))
        end
        return
      end
      last_err = ok and (start_err or started_or_err) or started_or_err
    end
    error("audio.i2s_start failed: " .. tostring(last_err or "start rejected"))
  end

  if not i2s or not i2s.start then
    error("missing i2s")
  end

  pcall(i2s.stop, APP.I2S_ID)
  for _, profile in ipairs(profiles) do
    local channel = i2s.CHANNEL_ONLY_LEFT or i2s.CHANNEL_RIGHT_LEFT
    if (tonumber(channels) or 1) > 1 then
      channel = i2s.CHANNEL_RIGHT_LEFT or i2s.CHANNEL_ALL_LEFT or i2s.CHANNEL_ONLY_LEFT
    end
    local ok, err = pcall(i2s.start, APP.I2S_ID, {
      mode = i2s.MODE_MASTER | i2s.MODE_TX,
      rate = rate,
      bits = APP.I2S_BITS,
      channel = channel,
      format = i2s.FORMAT_I2S,
      buffer_count = profile.count or APP.BUFFER_COUNT,
      buffer_len = profile.len or APP.BUFFER_LEN,
      data_out_pin = APP.DATA_OUT_PIN,
    })
    if ok then
      if profile.count ~= APP.BUFFER_COUNT or profile.len ~= APP.BUFFER_LEN then
        log("i2s dma fallback", tostring(profile.count) .. "x" .. tostring(profile.len))
      end
      return
    end
    last_err = err
  end
  error("i2s.start failed: " .. tostring(last_err))
end

local function start_native_i2s_play()
  if not APP.audio or not APP.audio.i2s_play_start then
    error("audio.i2s_play_start missing")
  end
  S.play_task_base_pcm_bytes = tonumber(S.pcm_bytes) or 0
  S.play_task_last_written_bytes = 0
  S.play_task_last_progress_ms = now_ms()
  S.play_task_stall_logged_ms = 0
  local ok, started_or_err, start_err = pcall(APP.audio.i2s_play_start, {
    chunk_bytes = APP.PLAY_TASK_CHUNK_BYTES,
    timeout_ms = APP.PLAY_TASK_TIMEOUT_MS,
    stack_bytes = APP.PLAY_TASK_STACK_BYTES,
    priority = APP.PLAY_TASK_PRIORITY,
    core = APP.PLAY_TASK_CORE,
    producer_stack_bytes = APP.PRODUCER_TASK_STACK_BYTES,
    producer_priority = APP.PRODUCER_TASK_PRIORITY,
    producer_core = APP.PRODUCER_TASK_CORE,
  })
  if not ok then
    error("audio.i2s_play_start failed: " .. tostring(started_or_err))
  end
  if not started_or_err then
    error("audio.i2s_play_start failed: " .. tostring(start_err or "start rejected"))
  end
  return true
end

local function pause_native_i2s(paused)
  if APP.audio and APP.audio.i2s_play_pause then
    return pcall(APP.audio.i2s_play_pause, paused and true or false)
  end
  return false
end

local function stop_i2s()
  if APP.audio and APP.audio.i2s_play_stop then
    pcall(APP.audio.i2s_play_stop)
  end
  if APP.audio and APP.audio.i2s_stop then
    pcall(APP.audio.i2s_stop)
    return
  end
  if i2s then
    pcall(i2s.mute, APP.I2S_ID)
    pcall(i2s.stop, APP.I2S_ID)
  end
end

local function sync_native_buffering(st)
  local buffering = type(st) == "table" and tonumber(st.buffering) == 1
  if buffering and not S.buffering then
    pause_play_clock()
    S.buffering = true
    S.buffering_reason = "pcm"
    S.status = "BUFFER"
    log("audio buffering:", tostring(st.pcm_buffer_bytes or 0) .. "/" .. tostring(st.pcm_buffer_capacity or 0))
  elseif (not buffering) and S.buffering then
    S.buffering = false
    S.buffering_reason = ""
    if S.playing then
      S.status = "PLAY"
      resume_play_clock()
    end
  end
end

local function close_audio()
  S.buffering = false
  S.buffering_reason = ""
  stop_i2s()
  if APP.audio and APP.audio.close then
    pcall(APP.audio.close)
  end
end

apply_audio_effects = function()
  local audio = APP.audio
  if not audio or not audio.set_effects then return end
  local eq = APP.eq_settings.eq or {}
  local ok, err = pcall(function()
audio.set_effects({
  volume = APP.eq_settings.volume or 0.44,

  vbass = APP.eq_settings.vbass,
  vbass_low_hpf = APP.eq_settings.vbass_low_hpf or 45,
  vbass_low_lpf = APP.eq_settings.vbass_low_lpf or 220,
  vbass_out_hpf = APP.eq_settings.vbass_out_hpf or 140,
  vbass_out_lpf = APP.eq_settings.vbass_out_lpf or 760,
  vbass_drive = APP.eq_settings.vbass_drive or 3.5,
  vbass_mix = APP.eq_settings.vbass_mix or 0.16,
  vbass_even = APP.eq_settings.vbass_even or 1.2,
  vbass_odd = APP.eq_settings.vbass_odd or 0.8,
  vbass_solo = APP.eq_settings.vbass_solo,

  hpf = true,
  hpf_freq = APP.eq_settings.hpf_freq or 120,
  hpf_q = 0.707,

  eq = true,
  eq_count = 7,

  -- 鼓点低频下沿，轻补，给一点下沉感
  eq1_freq = 160,
  eq1_gain = eq[1] or 6.0,
  eq1_q = 0.75,

  -- 鼓点主体 / 低音感，重点补
  eq2_freq = 250,
  eq2_gain = eq[2] or 5.5,
  eq2_q = 0.70,

  -- 人声浑厚度 / 鼓点身体感
  eq3_freq = 420,
  eq3_gain = eq[3] or 3.5,
  eq3_q = 0.8,

  -- 压桌面反射、箱声、BGM 低中频杂乱
  eq4_freq = 780,
  eq4_gain = eq[4] or 0.3,
  eq4_q = 1.0,

  -- 压塑料感、鼻音、伴奏拥挤
  eq5_freq = 1250,
  eq5_gain = eq[5] or -2.2,
  eq5_q = 1.0,

  -- 压鼓点偏高的“敲击头/啪声”
  eq6_freq = 2800,
  eq6_gain = eq[6] or -0.6,
  eq6_q = 0.85,

  -- 压 BGM 高频乱、刺、硬
  eq7_freq = 4300,
  eq7_gain = eq[7] or 0.8,
  eq7_q = 0.65,

  limiter = true,
  limiter_peak = APP.eq_settings.limiter_peak or 30000,
    })
  end)
  if ok then
    web_log("audio.set_effects ok", "volume=" .. tostring(APP.eq_settings.volume or 0.6))
  else
    web_log("audio.set_effects failed", tostring(err))
  end
end

local function set_error(msg)
  S.error = tostring(msg or "error")
  S.status = "ERR"
  S.playing = false
  log(S.error)
end

local function ensure_audio()
  if APP.audio then return APP.audio end
  local ok, mod_or_err = pcall(require, APP.MODULE_PATH)
  if not ok or not mod_or_err then
    error("audio module missing: " .. tostring(mod_or_err))
  end
  APP.audio = mod_or_err
  apply_audio_effects()
  return APP.audio
end

local function current_track()
  return APP.tracks[APP.index]
end

local function same_track(a, b)
  if not a or not b then return false end
  local ap = text_or(a.path, ""):lower()
  local bp = text_or(b.path, ""):lower()
  if ap ~= "" and bp ~= "" then
    return ap == bp
  end
  return text_or(a.name, ""):lower() == text_or(b.name, ""):lower()
end

local function find_track_index(track)
  if not track then return nil end
  for i, item in ipairs(APP.tracks or {}) do
    if same_track(item, track) then
      return i
    end
  end
  return nil
end

local function update_track_audio_info(info, track)
  if type(info) ~= "table" then return end
  S.sample_rate = tonumber(info.sample_rate) or S.sample_rate or 44100
  S.channels = tonumber(info.channels) or tonumber(APP.audio and APP.audio.OUTPUT_CHANNELS) or S.channels or 1
  if S.channels < 1 then S.channels = 2 end
  S.bytes_per_sec = S.sample_rate * S.channels * 2
  local info_bitrate = tonumber(info.bitrate) or 0
  if info_bitrate > 0 and info_bitrate < 10000 then
    info_bitrate = info_bitrate * 1000
  end
  local estimated = false
  if info_bitrate > 0 then
    S.bitrate = info_bitrate
  else
    local name = tostring(track and track.name or ""):lower()
    if (tonumber(S.bitrate) or 0) <= 0 and name:match("%.mp3$") then
      S.bitrate = tonumber(APP.MP3_FALLBACK_BITRATE) or 128000
      estimated = true
    end
  end
  S.file_size = tonumber(info.file_size) or tonumber(track and track.size) or S.file_size or 0
  local duration_ms = tonumber(info.duration_ms) or tonumber(info.duration) or 0
  if duration_ms > 0 and duration_ms < 10000 then
    duration_ms = duration_ms * 1000
  end
  if duration_ms > 0 and S.bitrate > 0 and S.file_size > 0 then
    local estimate_ms = bitrate_duration_ms(S.file_size, S.bitrate)
    if estimate_ms > 0 and (duration_ms > estimate_ms * 10 or duration_ms * 10 < estimate_ms) then
      duration_ms = estimate_ms
      estimated = true
    end
  end
  if duration_ms <= 0 and S.bitrate > 0 and S.file_size > 0 then
    duration_ms = bitrate_duration_ms(S.file_size, S.bitrate)
    estimated = estimated or info_bitrate <= 0
  end
  if duration_ms > 0 then
    S.duration_ms = duration_ms
    S.duration_estimated = estimated
  end
end

local function refresh_track_audio_info()
  if not (APP.audio and APP.audio.info) then return end
  local ok, info = pcall(function() return APP.audio.info() end)
  if ok then
    update_track_audio_info(info, current_track())
  end
end

local function open_track(index, autoplay, anchor_track, delta)
  if S.opening then return end
  S.opening = true
  close_audio()
  run_deferred_rescan("open", true)

  local n = #APP.tracks
  if n <= 0 then
    S.playing = false
    S.status = "EMPTY"
    S.opening = false
    return
  end

  if anchor_track then
    local anchor_index = find_track_index(anchor_track)
    if anchor_index then
      index = anchor_index + (delta or 0)
    end
  end

  while index < 1 do index = index + n end
  while index > n do index = index - n end
  APP.index = index

  local track = current_track()
  local ok, err = pcall(function()
    local audio = ensure_audio()
    apply_audio_effects()
    local open_path = text_or(track.path, track.name)
    local opened, open_err = audio.open(open_path)
    if not opened then
      error("audio.open failed: " .. tostring(open_err))
    end

    local info, info_err = audio.info()
    if not info then
      error("audio.info failed: " .. tostring(info_err))
    end

    S.duration_ms = 0
    S.file_size = tonumber(track.size) or 0
    S.bitrate = 0
    S.duration_estimated = false
    update_track_audio_info(info, track)
    S.pcm_bytes = 0
    S.play_task_base_pcm_bytes = 0
    S.play_task_last_written_bytes = 0
    S.play_task_last_progress_ms = now_ms()
    S.play_task_stall_logged_ms = 0
    S.eof_advanced = false
    S.lyric_idx = 1
    S.error = ""
    S.buffering = false
    S.buffering_reason = ""
    S.status = autoplay and "PLAY" or "PAUSE"
    load_lyrics(track)
    prefetch_audio(APP.MP3_PREFETCH_TARGET_BYTES, APP.MP3_PREFETCH_OPEN_BYTES)
    start_i2s(S.sample_rate, S.channels)
    reset_play_clock()
    reset_audio_stats()
    reset_profile()
    S.playing = autoplay and true or false
    if S.playing then
      start_native_i2s_play()
    end
    refresh_track_audio_info()
    if S.playing then
      feature_log("Now playing:", tostring(track.title or track.name or "unknown"), "(" .. tostring(APP.index) .. "/" .. tostring(n) .. ")")
    else
      feature_log("Track ready:", tostring(track.title or track.name or "unknown"), "(" .. tostring(APP.index) .. "/" .. tostring(n) .. ")")
    end
  end)

  if not ok then
    set_error(err)
    close_audio()
  end

  S.opening = false
end

local function pause_track()
  if not S.playing then return end
  pause_play_clock()
  S.playing = false
  S.buffering = false
  S.buffering_reason = ""
  S.status = "PAUSE"
  if not pause_native_i2s(true) then
    stop_i2s()
  end
  run_deferred_rescan("pause")
  feature_log("Playback paused:", tostring(current_track() and (current_track().title or current_track().name) or "unknown"))
end

local function resume_track()
  if S.playing or not current_track() then return end
  local resumed_native = false
  if APP.audio and APP.audio.i2s_play_state then
    local ok_state, st = pcall(APP.audio.i2s_play_state)
    if ok_state and st and tonumber(st.running) == 1 then
      local ok_pause, pause_err = pause_native_i2s(false)
      if not ok_pause then
        set_error(pause_err)
        return
      end
      resumed_native = true
    end
  end
  if not resumed_native then
    local ok, err = pcall(function()
      start_i2s(S.sample_rate, S.channels)
    end)
    if not ok then
      set_error(err)
      return
    end
    start_native_i2s_play()
  end
  resume_play_clock()
  S.playing = true
  S.status = "PLAY"
  feature_log("Playback resumed:", tostring(current_track() and (current_track().title or current_track().name) or "unknown"))
end

local function toggle_play()
  if #APP.tracks == 0 then return end
  if S.playing then
    pause_track()
  else
    resume_track()
  end
end

local function next_track(delta)
  if #APP.tracks == 0 then return end
  local step = tonumber(delta) or 1
  local from_track = current_track()
  if step < 0 then
    feature_log("Previous track requested")
  else
    feature_log("Next track requested")
  end
  open_track(APP.index + step, true, from_track, step)
end

local function play_tick()
  if not APP.running or S.in_tick or S.opening then return end
  if app and app.exiting and app.exiting() then
    APP.stop("exit")
    return
  end
  if not S.playing or not APP.audio then
    run_deferred_rescan("idle")
    return
  end

  local tick_start = APP.PROFILE_AUDIO and profile_now_us() or 0
  S.in_tick = true
  local advance_track = false
  local ok, err = pcall(function()
    if not APP.audio.i2s_play_state then
      error("audio.i2s_play_state missing")
    end

    local state_start = APP.PROFILE_AUDIO and profile_now_us() or 0
    local st, state_err = APP.audio.i2s_play_state()
    if (tonumber(S.duration_ms) or 0) <= 0 or S.duration_estimated then
      refresh_track_audio_info()
    end
    if APP.PROFILE_AUDIO then
      local total = tonumber(st and st.written_bytes) or S.pcm_bytes or 0
      local delta = math.max(0, total - (tonumber(S.pcm_bytes) or 0))
      prof_add("i2s_write", profile_elapsed_us(state_start), delta)
    end
    if not st then
      error("audio.i2s_play_state failed: " .. tostring(state_err))
    end
    sync_native_buffering(st)
    local written = tonumber(st.written_bytes) or tonumber(S.play_task_last_written_bytes) or 0
    local prev_written = tonumber(S.play_task_last_written_bytes) or 0
    local progress_now = now_ms()
    if written > prev_written then
      S.play_task_last_progress_ms = progress_now
      S.play_task_stall_logged_ms = 0
    elseif tonumber(st.running) == 1 and tonumber(st.paused) ~= 1 and tonumber(st.eof) ~= 1 and not S.buffering then
      local last_progress = tonumber(S.play_task_last_progress_ms) or progress_now
      local stalled_ms = math.max(0, progress_now - last_progress)
      local last_log = tonumber(S.play_task_stall_logged_ms) or 0
      if stalled_ms >= 300 and progress_now - last_log >= 1000 then
        S.play_task_stall_logged_ms = progress_now
        log(
          "audio i2s stall:",
          tostring(stalled_ms) .. "ms",
          "pcmb=" .. tostring(st.pcm_buffer_bytes or 0) .. "/" .. tostring(st.pcm_buffer_capacity or 0),
          "pending=" .. tostring(st.pending_bytes or 0),
          "iter=" .. tostring(st.iterations or 0)
        )
      end
    end
    S.play_task_last_written_bytes = written
    S.pcm_bytes = (tonumber(S.play_task_base_pcm_bytes) or 0) + written
    if tonumber(st.error) == 1 then
      error("audio play task failed: " .. tostring(st.last_error or "task error"))
    end
    if tonumber(st.eof) == 1 and not S.eof_advanced then
      S.eof_advanced = true
      advance_track = true
    end
  end)
  S.in_tick = false
  if APP.PROFILE_AUDIO then
    prof_add("play_tick", profile_elapsed_us(tick_start), 0)
  end

  if ok and advance_track then
    S.playing = false
    S.status = "NEXT"
    next_track(1)
    return
  end

  if not ok then
    set_error(err)
    close_audio()
  end
end

local function render_ui()
  if APP._ui_render then
    return APP._ui_render()
  end
end

local function build_ui()
  if APP._ui_build then
    return APP._ui_build()
  end
end

local function bind_touch()
  if APP._ui_bind_touch then
    return APP._ui_bind_touch()
  end
end

local long_repeat_state = {}

local function reset_repeat(code)
  long_repeat_state[code] = nil
end

local function should_repeat(evt_type, code)
  if evt_type == key.START or evt_type == key.SHORT then
    reset_repeat(code)
    return true
  elseif evt_type == key.LONG_START then
    long_repeat_state[code] = { count = 0 }
  elseif evt_type == key.LONG_REPEAT then
    local st = long_repeat_state[code] or { count = 0 }
    st.count = st.count + 1
    long_repeat_state[code] = st
    return st.count == 1 or (st.count % 5 == 0)
  elseif evt_type == key.LONG_END then
    reset_repeat(code)
  end
  return false
end

local function exit_app()
  APP.stop("exit")
  if app and app.exit then
    pcall(function() app.exit() end)
  end
end

local function bind_keys()
  if app and app.set_home_exit then
    pcall(function() app.set_home_exit(false) end)
  end
  if not key or not key.on then return end

  key.on(key.HOME, function(evt_type)
    if evt_type == key.SHORT then
      toggle_play()
    elseif evt_type == key.LONG_START or evt_type == key.EXIT then
      exit_app()
    end
  end)

  key.on(key.LEFT, function(evt_type, ts_ms)
    if should_repeat(evt_type, key.LEFT) then
      next_track(-1)
    end
  end)

  key.on(key.RIGHT, function(evt_type, ts_ms)
    if should_repeat(evt_type, key.RIGHT) then
      next_track(1)
    end
  end)
end

local function start_timers()
  if not tmr or not tmr.create then return end

  APP.timers.play = tmr.create()
  APP.timers.play:alarm(APP.PLAY_TICK_MS, tmr.ALARM_AUTO, play_tick)

  APP.timers.ui = tmr.create()
  APP.timers.ui:alarm(APP.UI_TICK_MS, tmr.ALARM_AUTO, render_ui)
end

local function load_ui_module()
  APP._call = call
  APP._text_or = text_or
  APP._clamp = clamp
  APP._asset = asset
  APP._elapsed_ms = play_position_ms
  APP._current_track = current_track
  APP._next_track = next_track
  APP._toggle_play = toggle_play
  APP._lyric_text_at = lyric_text_at
  APP._lyric_scroll_px = lyric_scroll_px
  APP._profile_now_us = profile_now_us
  APP._profile_elapsed_us = profile_elapsed_us
  APP._prof_add = prof_add
  APP._maybe_log_profile = maybe_log_profile

  local path = APP.APP_DIR .. "/ui.lua"
  if not file or not file.getcontents then
    error("file.getcontents is not available")
  end
  if not load then
    error("load is not available")
  end

  local source = file.getcontents(path)
  if type(source) ~= "string" or source == "" then
    error("read ui.lua failed: " .. path)
  end

  local loader, err = load(source, "@" .. path)
  if not loader then
    error("compile ui.lua failed: " .. tostring(err))
  end

  local ok, factory_or_err = pcall(loader)
  if not ok then
    error("run ui.lua failed: " .. tostring(factory_or_err))
  end
  if type(factory_or_err) ~= "function" then
    error("ui.lua must return function(APP)")
  end

  local init_ok, init_err = pcall(factory_or_err, APP)
  if not init_ok then
    error("init ui.lua failed: " .. tostring(init_err))
  end
  if not (APP._ui_load_font and APP._ui_release_fonts and APP._ui_build and APP._ui_render and APP._ui_bind_touch and APP._ui_show_loading) then
    error("ui.lua did not export required UI functions")
  end
end

local function loading_status(text)
  if APP._ui_set_loading_status then
    APP._ui_set_loading_status(text)
  end
end

local function after_loading_frame(fn)
  if not APP.running then return end
  if tmr and tmr.create then
    local timer = tmr.create()
    APP.timers.startup = timer
    timer:alarm(30, tmr.ALARM_SINGLE or 0, function()
      APP.timers.startup = nil
      pcall(function() timer:unregister() end)
      if APP.running then
        fn()
      end
    end)
  else
    fn()
  end
end

function APP.stop(reason)
  if not APP.running then return end
  APP.running = false
  S.playing = false
  if APP.timers.eq_save then
    local timer = APP.timers.eq_save
    APP.timers.eq_save = nil
    pcall(function() timer:stop() end)
    pcall(function() timer:unregister() end)
    save_eq_settings_now()
  end
  for _, timer in pairs(APP.timers) do
    stop_timer(timer)
  end
  APP.timers = {}
  if lv_obj_remove_event_dsc then
    for _, item in ipairs(APP.events or {}) do
      pcall(function() lv_obj_remove_event_dsc(item.obj, item.dsc) end)
    end
  end
  APP.events = {}
  close_audio()
  if key and key.off then
    pcall(key.off, key.HOME)
    pcall(key.off, key.LEFT)
    pcall(key.off, key.RIGHT)
  end
  if app and app.set_home_exit then
    pcall(function() app.set_home_exit(true) end)
  end
  if APP.web_started and httpd and httpd.stop then
    pcall(httpd.stop)
    APP.web_started = false
  end
  if APP._ui_release_fonts then
    APP._ui_release_fonts()
  end
end

load_eq_settings()
load_ui_module()
APP._ui_show_loading("Loading fonts")
after_loading_frame(function()
  APP.font_cn = APP._ui_load_font(APP.FONT_DIR .. "/msyh_cn_13.bin", FONT_14)
  APP.font_big = APP._ui_load_font(APP.FONT_DIR .. "/18chinese.bin", APP.font_cn)

  loading_status("Loading audio module")
  after_loading_frame(function()
    local audio_ready, audio_err = pcall(ensure_audio)
    if not audio_ready then
      S.error = tostring(audio_err or "audio module failed")
      S.status = "ERR"
      log(S.error)
    end

    loading_status("Starting web")
    after_loading_frame(function()
      start_web()

      loading_status("Preparing audio")
      after_loading_frame(function()
        loading_status("Scanning music")
        after_loading_frame(function()
          APP.tracks = scan_tracks()

          loading_status(audio_ready and #APP.tracks > 0 and "Opening track" or "Opening player")
          after_loading_frame(function()
            if audio_ready and #APP.tracks > 0 then
              open_track(1, true)
            elseif #APP.tracks <= 0 then
              S.status = "EMPTY"
            end

            loading_status("Opening player")
            after_loading_frame(function()
              build_ui()
              bind_keys()
              bind_touch()
              start_timers()

              render_ui()
            end)
          end)
        end)
      end)
    end)
  end)
end)
