local M = { language = "en" }
local function normalize(value)
  local v = tostring(value or ""):lower():gsub("_", "-")
  if v == "de" or v:match("^de%-") then return "de" end
  if v == "ja" or v:match("^ja%-") then return "ja" end
  if v == "zh" or v:match("^zh%-") or v == "" then return "zh-CN" end
  return "en"
end
if file and file.getcontents then
  local ok, raw = pcall(file.getcontents, "/sd/apps/settings.json")
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  if ok and raw and codec and codec.decode then
    local decoded, doc = pcall(codec.decode, raw)
    if decoded and type(doc) == "table" then M.language = normalize(doc.language or doc.locale or doc.lang) end
  end
end

-- Original Chinese strings are display keys, never protocol values or device IDs.
local words = {
  ["蓝牙手柄"]={"Controller","Controller","コントローラー"},
  ["亮度"]={"Brightness","Helligkeit","明るさ"},
  ["json.encode 不可用"]={"JSON encoder unavailable","JSON-Encoder nicht verfügbar","JSON エンコーダーがありません"},
  ["json.decode 不可用"]={"JSON decoder unavailable","JSON-Decoder nicht verfügbar","JSON デコーダーがありません"},
  ["状态格式错误"]={"Invalid status format","Ungültiges Statusformat","状態データが不正です"},
  ["不可用"]={"Unavailable","Nicht verfügbar","利用不可"},
  ["关闭"]={"Off","Aus","オフ"}, ["开启"]={"On","Ein","オン"},
  ["客户端"]={"Client","Client","クライアント"}, ["热点"]={"Hotspot","Hotspot","アクセスポイント"},
  ["客户端+热点"]={"Client + hotspot","Client + Hotspot","接続 + AP"},
  ["未安装"]={"Not installed","Nicht installiert","未インストール"},
  ["不支持"]={"Unsupported","Nicht unterstützt","非対応"},
  ["已禁用"]={"Disabled","Deaktiviert","無効"}, ["已连接"]={"Connected","Verbunden","接続済み"},
  ["连接中"]={"Connecting","Verbindet","接続中"}, ["扫描中"]={"Scanning","Sucht","検索中"},
  ["已开启"]={"Enabled","Aktiviert","有効"}, ["设置"]={"Settings","Einstellungen","設定"},
  ["亮度 "]={"Brightness ","Helligkeit ","明るさ "}, ["蓝牙手柄 "]={"Controller ","Controller ","コントローラー "},
  ["手柄通信不可用"]={"Controller communication unavailable","Controller-Verbindung nicht verfügbar","コントローラーと通信できません"},
  ["手柄服务未运行"]={"Controller service is stopped","Controller-Dienst ist gestoppt","コントローラーサービス停止中"},
  ["读取失败"]={"Read failed","Lesefehler","読み込み失敗"},
  ["← 关闭  切换 →"]={"← Off  Switch →","← Aus  Wechsel →","← オフ  切替 →"},
  ["未启用"]={"Disabled","Deaktiviert","無効"},
  ["← 关闭  开启 →"]={"← Off  On →","← Aus  Ein →","← オフ  オン →"},
  ["要连接手柄请先安装 HID Pad 服务"]={"Install HID Pad to connect","Zum Verbinden HID Pad installieren","接続には HID Pad が必要です"},
  ["← 关闭  重扫 →"]={"← Off  Rescan →","← Aus  Neu suchen →","← オフ  再検索 →"},
  ["服务未运行"]={"Service stopped","Dienst gestoppt","サービス停止中"},
  ["→ 启动服务"]={"→ Start service","→ Dienst starten","→ サービス開始"},
  ["BLE 驱动已停止"]={"BLE driver stopped","BLE-Treiber gestoppt","BLE ドライバー停止中"},
  ["按键 "]={"Buttons ","Tasten ","ボタン "},
  ["正在连接手柄"]={"Connecting controller","Controller verbindet","コントローラー接続中"},
  ["发现 "]={"Found ","Gefunden: ","検出: "}, [" 个设备"]={" devices"," Geräte"," 台"},
  ["正在查找手柄"]={"Searching for controller","Controller wird gesucht","コントローラーを検索中"},
  ["等待设备"]={"Waiting for device","Warte auf Gerät","デバイス待ち"},
  ["← 降低  提高 →"]={"← Lower  Higher →","← Weniger  Mehr →","← 暗く  明るく →"},
  ["未分配 IP"]={"No IP address","Keine IP-Adresse","IP アドレス未取得"},
  ["Wi-Fi 设置失败"]={"Wi-Fi setup failed","WLAN-Einstellung fehlgeschlagen","Wi-Fi 設定失敗"},
  ["Wi-Fi 启动失败"]={"Wi-Fi start failed","WLAN-Start fehlgeschlagen","Wi-Fi 起動失敗"},
  ["Wi-Fi 不可用"]={"Wi-Fi unavailable","WLAN nicht verfügbar","Wi-Fi 利用不可"},
  ["Wi-Fi 关闭失败"]={"Wi-Fi stop failed","WLAN-Stopp fehlgeschlagen","Wi-Fi 停止失敗"},
  ["Wi-Fi 已关闭"]={"Wi-Fi off","WLAN ausgeschaltet","Wi-Fi オフ"},
  ["蓝牙手柄不支持"]={"Controller unsupported","Controller nicht unterstützt","コントローラー非対応"},
  ["手柄服务启动失败"]={"Controller service failed to start","Controller-Dienst konnte nicht starten","コントローラーサービス起動失敗"},
  ["手柄服务启动中"]={"Starting controller service","Controller-Dienst startet","コントローラーサービス起動中"},
  ["等待手柄服务"]={"Waiting for controller service","Warte auf Controller-Dienst","コントローラーサービス待ち"},
  ["蓝牙手柄正在开启"]={"Enabling controller","Controller wird aktiviert","コントローラーを有効化中"},
  ["蓝牙手柄正在关闭"]={"Disabling controller","Controller wird deaktiviert","コントローラーを無効化中"},
  ["蓝牙手柄重新扫描"]={"Rescanning controllers","Controller erneut suchen","コントローラー再検索"},
  ["亮度不可用"]={"Brightness unavailable","Helligkeit nicht verfügbar","明るさを変更できません"},
  ["亮度设置失败"]={"Brightness update failed","Helligkeit konnte nicht geändert werden","明るさの設定失敗"},
  ["设备信息"]={"Device info","Geräteinfo","デバイス情報"},
  ["操作失败"]={"Operation failed","Aktion fehlgeschlagen","操作失敗"},
  ["左右切换页面"]={"Left/right: pages","Links/rechts: Seiten","左右でページ切替"},
  [" / 余 "]={" / Free "," / Frei "," / 空き "},
  ["处理器"]={"Processor","Prozessor","プロセッサー"}, ["运存"]={"Memory","Arbeitsspeicher","メモリ"},
  ["SD卡"]={"SD card","SD-Karte","SD カード"}, ["系统版本"]={"Firmware","Firmware","ファームウェア"},
  ["IP 地址"]={"IP address","IP-Adresse","IP アドレス"},
  ["上下选择  左右调整  A 确认"]={"Up/down: select  L/R: adjust  A: OK","Oben/unten: Wahl  L/R: Wert  A: OK","上下: 選択  左右: 調整  A: 決定"},
  ["B 返回设置  Select/Home 退出"]={"B: Settings  Select/Home: exit","B: Einstellungen  Select/Home: Ende","B: 設定  Select/Home: 終了"},
  ["强制退出"]={"Force exit","Beenden erzwingen","強制終了"}, ["返回上级"]={"Back","Zurück","戻る"},
  ["按键映射不可用"]={"Button mapping unavailable","Tastenbelegung nicht verfügbar","ボタン割り当て利用不可"},
}
function M.t(text)
  if M.language == "zh-CN" then return text end
  local values = words[text]
  return values and (values[M.language == "de" and 2 or M.language == "ja" and 3 or 1] or values[1]) or text
end
return M
