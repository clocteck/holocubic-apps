local M = {}
local function normalize(v)
  v = tostring(v or ""):lower():gsub("_", "-")
  if v:match("^en") then return "en" end
  if v:match("^ja") then return "ja" end
  if v:match("^de") then return "de" end
  if v == "zh-tw" or v:match("^zh%-hant") or v == "zh-hk" then return "zh-TW" end
  return "zh-CN"
end
function M.locale(cfg)
  local lang = cfg and cfg.LANGUAGE
  local lib = rawget(_G, "json") or rawget(_G, "sjson")
  local function read(path)
    local ok, raw = pcall(file.getcontents, path)
    if ok and lib then local good, doc = pcall(lib.decode, raw); if good and type(doc) == "table" then return doc end end
    return {}
  end
  if not lang then lang = read("/sd/data/xiaozhi/config.json").language end
  if not lang or lang == "auto" then
    local settings = read("/sd/apps/settings.json")
    lang = settings.language or settings.locale or settings.lang
  end
  return normalize(lang)
end
local en = {
  ["配对码："]="Pairing code: ", ["请在 xiaozhi.me 输入"]="Enter in xiaozhi.me",
  ["配对等待超时，后台继续重试"]="Pairing wait timed out; retrying in the background",
  ["未配置 ota.url"]="OTA URL not configured", ["等待设备 MAC"]="Waiting for device identity", ["正在读取设备 MAC"]="Reading device identity",
  ["检查 OTA"]="Checking OTA", ["正在向小智服务端申请验证码"]="Requesting pairing code", ["验证码 "]="Pairing code ",
  ["后台添加设备输入验证码 "]="Enter this code in the console: ", ["等待绑定"]="Waiting for pairing", ["等待后台设备绑定"]="Waiting for device pairing",
  ["绑定成功"]="Paired", ["绑定成功，正在读取服务配置"]="Paired; loading server configuration", ["小智已就绪"]="Ready", ["激活失败"]="Pairing failed",
  ["配置"]="Configuration", ["存储接口不可用"]="Storage API unavailable", ["保存失败"]="Save failed", ["主应用 UI 类型无效"]="Invalid app style",
  ["主应用 UI 文件不存在"]="App style is not installed", ["音量值无效"]="Invalid volume", ["OTA 地址必须以 http:// 或 https:// 开头"]="OTA URL must start with http:// or https://",
  ["服务器地址必须以 ws:// 或 wss:// 开头"]="Server URL must start with ws:// or wss://", ["协议版本仅支持 1 到 3"]="Unsupported protocol version",
  ["后台 UI 模式仅支持 app 或 floating"]="UI mode must be app or floating", ["悬浮 UI 文件不存在"]="Floating style is not installed", ["服务配置"]="Service configuration",
  ["获取验证码"]="Pairing code", ["正在获取配对码"]="Requesting pairing code", ["未配置 OTA"]="OTA not configured",
  ["网络暂时繁忙，仍在等待后台绑定"]="Network busy; waiting for pairing", ["网络暂时繁忙，正在重新获取配对信息"]="Network busy; retrying pairing",
  ["正在重试"]="Retrying", ["编码失败"]="Encoding failed", ["主应用配置"]="App configuration", ["服务配置存储接口不可用"]="Service storage unavailable",
  ["服务配置编码失败"]="Service configuration encoding failed", ["服务配置保存失败"]="Service configuration save failed", ["已切换自定义服务"]="Server changed",
  ["自定义服务"]="Custom server", ["自定义服务已保存，唤醒后连接"]="Server saved; wake to connect", ["自定义服务已保存"]="Server saved",
  ["自动休眠时间仅支持 10、20、30 或 60 秒"]="Idle timeout must be 10, 20, 30 or 60 seconds", ["未安装小智前台 App，不能选择打开 App"]="XiaoZhi frontend is not installed",
  ["后台 UI 类型无效"]="Invalid floating style", ["悬浮角色文件不存在"]="Character is not installed", ["UI 配置已保存，已立即生效"]="UI settings applied",
  ["设备身份已修改，正在重新获取配对码"]="Identity changed; requesting pairing code", ["设备身份已修改，正在重启服务"]="Identity changed; restarting",
  ["在后台添加设备输入验证码"]="Enter the pairing code in the console",
  ["小智待命中"]="Ready", ["验证码"]="Pairing code", ["正在启动"]="Starting",
  ["正在连接服务"]="Connecting", ["正在连接"]="Connecting", ["我在听"]="Listening",
  ["小智正在回答"]="Speaking", ["启动失败"]="Startup failed", ["发生错误"]="Error", ["音频处理失败"]="Audio processing failed",
  ["正在初始化"]="Initializing", ["微信气泡模式"]="Chat bubbles", ["官方字幕模式"]="Subtitles",
  ["启动中"]="Starting", ["配网中"]="Wi-Fi setup", ["激活中"]="Pairing", ["待命"]="Ready",
  ["连接中"]="Connecting", ["聆听中"]="Listening", ["回答中"]="Speaking", ["升级中"]="Updating",
  ["音频测试"]="Audio test", ["错误"]="Error", ["连接失败"]="Connection failed",
  ["未配置 websocket"]="Server not configured", ["缺少唤醒模型"]="Wake model missing",
  ["等待小智服务"]="Waiting for XiaoZhi Service", ["听"]="Listen", ["说"]="Speak", ["休"]="Idle",
  ["笑"]="Smile", ["乐"]="Happy", ["忧"]="Sad", ["怒"]="Angry", ["哭"]="Cry",
  ["爱"]="Love", ["羞"]="Shy", ["惊"]="Wow", ["想"]="Think", ["眨"]="Wink",
  ["酷"]="Cool", ["松"]="Relax", ["馋"]="Yum", ["亲"]="Kiss", ["稳"]="Sure",
  ["玩"]="Fun", ["云"]="Cloud", ["链"]="Link",
}
local extra = {
  ["zh-TW"]={ ["Pairing code"]="配對碼", ["Starting"]="啟動中", ["Connecting"]="連線中", ["Listening"]="聆聽中", ["Speaking"]="回答中", ["Ready"]="待命", ["Error"]="錯誤", ["Startup failed"]="啟動失敗", ["Wi-Fi setup"]="網路設定", ["Pairing"]="配對中", ["Updating"]="更新中", ["Initializing"]="初始化中", ["Chat bubbles"]="聊天氣泡", ["Subtitles"]="字幕", ["Audio test"]="音訊測試", ["Connection failed"]="連線失敗", ["Server not configured"]="尚未設定伺服器", ["Wake model missing"]="缺少喚醒模型", ["Waiting for XiaoZhi Service"]="等待小智服務" },
  de={ ["Pairing code"]="Kopplungscode", ["Starting"]="Starten", ["Connecting"]="Verbinden", ["Listening"]="Zuhören", ["Speaking"]="Antwort", ["Ready"]="Bereit", ["Error"]="Fehler", ["Startup failed"]="Start fehlgeschlagen", ["Wi-Fi setup"]="WLAN einrichten", ["Pairing"]="Koppeln", ["Updating"]="Aktualisieren", ["Initializing"]="Initialisieren", ["Chat bubbles"]="Chatblasen", ["Subtitles"]="Untertitel", ["Audio test"]="Audiotest" },
  ja={ ["Pairing code"]="ペアリングコード", ["Starting"]="起動中", ["Connecting"]="接続中", ["Listening"]="聞いています", ["Speaking"]="回答中", ["Ready"]="待機", ["Error"]="エラー", ["Startup failed"]="起動失敗", ["Wi-Fi setup"]="Wi-Fi設定", ["Pairing"]="ペアリング中", ["Updating"]="更新中", ["Initializing"]="初期化中", ["Chat bubbles"]="チャット", ["Subtitles"]="字幕", ["Audio test"]="音声テスト" },
}
function M.translator(cfg)
  local lang = M.locale(cfg)
  return function(s)
    if lang == "zh-CN" or type(s) ~= "string" then return s end
    local translated = en[s]
    if not translated then return s end
    return extra[lang] and extra[lang][translated] or translated
  end
end
function M.pairing_prompt(code, cfg)
  local T = M.translator(cfg)
  local labels = {
    ["zh-TW"] = { "配對碼：", "請在 xiaozhi.me 輸入" },
    de = { "Kopplungscode: ", "Auf xiaozhi.me eingeben" },
    ja = { "ペアリングコード：", "xiaozhi.me で入力" },
  }
  local localized = labels[M.locale(cfg)]
  local title = (localized and localized[1] or T("配对码：")) .. tostring(code or "")
  local hint = localized and localized[2] or T("请在 xiaozhi.me 输入")
  return title, hint, title .. "\n" .. hint
end
return M
