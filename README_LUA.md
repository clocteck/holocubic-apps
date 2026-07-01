# Lua 使用说明

本文只说明 Lua 脚本中常用接口的写法。LVGL 控件、样式、布局和动画接口见 `README_LVGL.md`。

## 与 NodeMCU 的关系

本项目的 Lua 接口尽量沿用 NodeMCU 的模块命名和事件驱动风格。遇到细节不确定时，优先参考 NodeMCU ESP32 文档：

- NodeMCU ESP32 文档：https://nodemcu.readthedocs.io/en/dev-esp32/

本文按学习成本分成两类：

- `完全兼容接口`：名称、调用风格和 NodeMCU ESP32 基本一致，可以直接按官方模块文档理解。
- `扩展接口`：本项目新增模块，或在 NodeMCU 风格上做了便捷扩展；这些接口以本文为准。
- 有问题可以联系q群 780412532 反馈

## 兼容速查


 完全兼容 :`tmr`、`sjson`、`time`、`wifi`、`net`、`httpd`、`i2s`、`mqtt`
|扩展接口 : `file`、`http`、`websocket`、`zlib`、`np`、`viper`、`app`、`sys`、`key`、`nes`
## 基本约定

- 内置模块已经注册为全局表，不需要 `require`，例如 `tmr`、`file`、`wifi`、`http`。
- 文件路径建议显式使用 `/sd/...`。未写前缀时通常按 SD 根目录处理。
- 网络、按键、定时器、HTTPD 等回调都在 Lua 运行时里执行，回调中不要长时间阻塞。
- 周期任务优先使用 `tmr`。长循环里要用 `app.exiting()` 或 `sleep(ms)` 判断是否退出。
- 常见返回风格是 `value | nil, err`，但部分兼容接口使用 `bool`、抛错或回调状态码，见下方返回值速查。


## 最小示例

定时器：

```lua
local t = tmr.create()

t:alarm(1000, tmr.ALARM_AUTO, function()
  print("tick", tmr.time())
end)
```

WiFi 连接：

```lua
wifi.mode(wifi.STATION, false)
wifi.start()

wifi.sta.on("got_ip", function(_, info)
  print("ip:", info.ip)
end)

wifi.sta.config({
  ssid = "mywifi",
  pwd = "12345678"
}, false)

wifi.sta.connect()
```

HTTP 请求：

```lua
http.get("https://example.com/", {}, function(code, body)
  if code ~= 200 or not body then
    print("http failed:", code)
    return
  end

  print(body)
end)
```



## 事件与资源释放

- `tmr.delay(us)` 是忙等，只适合很短的硬件时序等待；网络、UI、文件操作中不要用它做长延时。
- `tmr.ALARM_AUTO` 定时器不用时调用 `timer:unregister()`。
- `app.on("key", fn)`、`key.on(...)`、`wifi.sta.on(...)`、`socket:on(...)` 注册后，退出或重建页面时要解绑。
- HTTPD 动态 handler 里打开的文件要在 `body` 生成结束时关闭。静态文件服务和 Lua VM 可能并发访问同一文件，动态读取更可控。

## 完全兼容接口

### tmr 定时器

常量：`tmr.ALARM_SINGLE`、`tmr.ALARM_AUTO`、`tmr.ALARM_SEMI`。

常用接口：

- `tmr.create() -> timer`
- `tmr.delay(us)`
- `tmr.now() -> us`
- `tmr.time() -> s`
- `tmr.softwd(seconds[, callback])`
- `tmr.wdclr()`
- `timer:alarm(interval_ms, mode, callback) -> bool`
- `timer:register(interval_ms, mode, callback)`
- `timer:start() -> bool`
- `timer:stop() -> bool`
- `timer:unregister()`
- `timer:interval(interval_ms)`
- `timer:state() -> started, mode | nil`

### sjson

`sjson` 按抛错风格使用，解析外部输入时建议配合 `pcall`。

- `sjson.encode(value[, opts]) -> string`
- `sjson.decode(text[, opts]) -> value`
- `sjson.encoder(value[, opts]) -> encoder`
- `encoder:read([size]) -> string|nil`
- `sjson.decoder([opts]) -> decoder`
- `decoder:write(chunk) -> value|nil`
- `decoder:result() -> value`

### time 时间

- `time.get() -> sec, usec`
- `time.set(sec[, usec])`
- `time.getlocal() -> table`
- `time.settimezone(timezone)`
- `time.initntp([server])`
- `time.ntpenabled() -> bool`
- `time.ntpstop()`
- `time.epoch2cal(sec) -> table`
- `time.cal2epoch(calendar) -> sec`

### wifi

常用模式：`wifi.NULLMODE`、`wifi.STATION`、`wifi.SOFTAP`、`wifi.STATIONAP`。

- `wifi.mode(mode[, save])`
- `wifi.start()`
- `wifi.stop()`
- `wifi.getmode() -> mode`
- `wifi.getchannel() -> primary, secondary`
- `wifi.sta.config(cfg[, save])`
- `wifi.sta.connect()`
- `wifi.sta.disconnect()`
- `wifi.sta.getip() -> ip, netmask, gateway | nil`
- `wifi.sta.getmac() -> mac`
- `wifi.sta.scan(cfg, callback)`
- `wifi.sta.on(event, callback_or_nil)`
- `wifi.ap.config(cfg[, save])`
- `wifi.ap.getip() -> ip, netmask, gateway | nil`
- `wifi.ap.on(event, callback_or_nil)`

常用 station 事件：`"start"`、`"stop"`、`"connected"`、`"disconnected"`、`"got_ip"`。

### net TCP/UDP

常量：`net.TCP`、`net.UDP`。常用事件：`"connection"`、`"receive"`、`"sent"`、`"disconnection"`、`"dns"`。

- `net.createConnection([type[, secure]]) -> socket|udpsocket`
- `net.createServer([type[, timeout]]) -> server|udpsocket`
- `net.createUDPSocket() -> udpsocket`
- `net.dns.resolve(host, callback)`
- `socket:on(event, callback_or_nil)`
- `socket:connect(port, host)`
- `socket:send(data[, callback])`
- `socket:close()`
- `server:listen([port][, ip], callback)`
- `udpsocket:listen([port][, ip])`
- `udpsocket:send(port, ip, data)`

### httpd HTTP 服务

`httpd` 用于设备端 HTTP 服务。静态文件从 `webroot` 下提供，动态路由由 Lua handler 返回响应 table。

- `httpd.start(config)`
- `httpd.stop()`
- `httpd.static(route, content_type) -> nil|err`
- `httpd.dynamic(method, route, handler) -> nil|err`
- `httpd.unregister(method, route) -> 1|nil`

`config` 常用字段：`webroot`、`auto_index`、`max_handlers`。

动态 handler 常用 `req` 字段：`method`、`uri`、`query`、`headers`、`getbody()`。

响应 table 常用字段：`status`、`type`、`headers`、`body`、`getbody`。`body` 和 `getbody` 二选一。


### i2s

- `i2s.start(i2s_num, cfg[, callback])`
- `i2s.stop(i2s_num)`
- `i2s.read(i2s_num, size[, wait_ms]) -> string`
- `i2s.write(i2s_num, data)`
- `i2s.mute(i2s_num)`

`cfg` 常用字段：`mode`、`rate`、`bits`、`channel`、`format`、`buffer_count`、`buffer_len`、`data_out_pin`。

### mqtt

常用事件：`"connect"`、`"connfail"`、`"offline"`、`"message"`、`"suback"`、`"unsuback"`、`"puback"`。

- `mqtt.Client(clientid, keepalive[, username[, password[, cleansession]]]) -> client`
- `client:on(event, callback_or_nil)`
- `client:connect(host[, port[, secure[, autoreconnect]]][, on_connect[, on_fail]]) -> bool`
- `client:publish(topic, payload, qos, retain[, callback]) -> bool`
- `client:subscribe(topic_or_table, qos_or_callback[, callback]) -> bool`
- `client:unsubscribe(topic_or_table[, callback]) -> bool`
- `client:lwt(topic, message[, qos[, retain]])`
- `client:close()`

## 扩展接口

### file 文件

`file` 保留 NodeMCU 常用文件接口，同时增加目录遍历、文件状态和整文件读写。路径优先写 `/sd/...`。

核心接口：

- `file.open(path[, mode]) -> fd|nil`
- `file.close([fd])`
- `file.read([fd][, n_or_char]) -> string|nil`
- `file.readline([fd]) -> string|nil`
- `file.write([fd], data) -> true|nil`
- `file.writeline([fd], data) -> true|nil`
- `file.seek([fd][, whence[, offset]]) -> pos|nil`
- `file.flush([fd]) -> true|nil`
- `file.exists(path) -> bool`
- `file.list([pattern]) -> table`
- `file.mkdir(path) -> bool`
- `file.rmdir(path) -> bool`
- `file.remove(path)`
- `file.rename(old, new) -> bool`
- `file.fsinfo() -> remain, used, total`

扩展接口：

- `file.listdir([dir]) -> array`
- `file.stat(path) -> table|nil`
- `file.getcontents(path) -> string|nil`
- `file.putcontents(path, contents) -> true|nil`

`mode` 常用值：`"r"`、`"w"`、`"a"`、`"r+"`、`"w+"`、`"a+"`。`whence` 常用值：`"set"`、`"cur"`、`"end"`。

```lua
local fd = file.open("/sd/test.txt", "w+")
if fd then
  fd:writeline("hello")
  fd:seek("set", 0)
  print(fd:readline())
  fd:close()
end

for _, e in ipairs(file.listdir("/sd")) do
  print(e.name, e.size, e.is_dir)
end
```

### http 请求

`http` 是便捷请求层。无 `callback` 时同步返回 `code, body, headers`；有 `callback` 时异步调用 `callback(code, body, headers)`。

- `http.get(url[, options][, callback])`
- `http.post(url, options, body[, callback])`
- `http.put(url, options, body[, callback])`
- `http.delete(url[, options][, body][, callback])`
- `http.request(url, method[, options][, body][, callback])`
- `http.createConnection(url[, method][, options]) -> connection`

`options` 常用字段：`headers`、`timeout`、`max_redirects`、`cert`、`bufsz`。

```lua
local code, body = http.get("http://example.com")
print("sync:", code, body)

http.post("https://httpbin.org/post", {
  headers = { ["Content-Type"] = "text/plain" }
}, "hello", function(code)
  print("post:", code)
end)
```

连接对象适合流式读取、复用连接或延迟 ack：

- `connection:on(event[, callback])`
- `connection:request()`
- `connection:setmethod(method)`
- `connection:seturl(url)`
- `connection:setheader(name[, value])`
- `connection:setbody([data])`
- `connection:ack()`
- `connection:close()`

事件名：`"connect"`、`"headers"`、`"data"`、`"complete"`。

### websocket

- `websocket.createClient() -> client`
- `client:config(params)`
- `client:connect(url)`
- `client:on(event, callback_or_nil)`
- `client:send(message[, opcode]) -> nil|err`
- `client:close()`

常量：`websocket.TEXT`、`websocket.BINARY`。事件名：`"connection"`、`"receive"`、`"close"`。

### zlib 压缩

- `zlib.isgzip(data) -> bool`
- `zlib.gunzip(data) -> string|nil, err`
- `zlib.inflate(data) -> string|nil, err`
- `zlib.crc32(data[, crc]) -> integer`

### np 数组计算

`np` 用于简单数组、矩阵、FFT 等计算。数组直接访问是 Lua 风格 `1-based`，`viper.buf` 仍是 `0-based`。

创建与转换：

- `np.array(table_or_array[, dtype]) -> array`
- `np.zeros(shape[, dtype]) -> array`
- `np.empty(shape[, dtype]) -> array`
- `np.frombuffer(buffer[, dtype[, count[, offset]]]) -> array`
- `np.shape(array) -> table`
- `array:shape() -> table`
- `array:to_table() -> table`
- `array:fill(value)`

常用计算：

- `np.add(a, b[, out])`
- `np.multiply(a, b[, out])`
- `np.divide(a, b[, out])`
- `np.sqrt(a[, out])`
- `np.square(a[, out])`
- `np.clip(a, min, max[, out])`
- `np.where(cond, x, y[, out])`
- `np.sum(a[, axis_or_options[, out]])`
- `np.matmul(a, b[, out])`
- `np.convolve2d(src, kernel[, out_or_options[, options]])`
- `np.hanning(M) -> array`
- `np.fft.rfft(a[, n]) -> re, im`
- `np.fft.rfftfreq(n[, d]) -> array`

```lua
local a = np.array({1, 2, 3})
local b = np.array({10, 20, 30})
local out = np.empty(np.shape(a))

np.add(a, b, out)
np.multiply(out, 2, out)

print(out:to_table()[1])
```

### viper 热路径函数

`viper` 用于把短小的 C-like 函数编译成机器码后给 Lua 调用，热点循环比直接lua代码快10倍以上。
viper库已在github上开源，可以参考 https://github.com/clocteck/esp32-viper

- `viper.compile_c(source[, opts]) -> fn`
- `viper.buf(size) -> buffer`
- `buffer:len() -> bytes`
- `buffer:get8(index) / buffer:set8(index, value)`
- `buffer:get16(index) / buffer:set16(index, value)`
- `buffer:get32(index) / buffer:set32(index, value)`
- `buffer:getf32(index) / buffer:setf32(index, value)`

buffer 下标使用 `0-based`。指针参数默认传 `viper.buf`。

```lua
local src = [=[
uint32_t sum8(uint8_t *buf, int32_t n) {
  uint32_t sum = 0;
  for (int32_t i = 0; i < n; i = i + 1) {
    sum = sum + buf[i];
  }
  return sum;
}
]=]

local fn = viper.compile_c(src)
local buf = viper.buf(16)
buf:set8(0, 10)
buf:set8(1, 20)
print(fn(buf, buf:len()))
```

### app 应用管理

`app` 用于和应用管理器交互。普通 app 最常用的是判断退出、主动退出、启动其他 app、注册 app 级事件。

- `app.exiting() -> bool`：长循环里判断是否正在退出。
- `app.exit() -> true|nil, err`：请求退出当前 app。
- `app.on(name, callback_or_nil)`：注册或取消 app 事件。
- `app.list() -> array`：获取 app 列表。
- `app.current() -> table|nil`：获取当前 app 信息。
- `app.launch(id) -> true|nil, err`：启动指定 app。
- `app.last_error() -> string|nil`：读取最近一次 app 错误。
- `app.rescan() -> true|nil, err`：重新扫描 app 列表。

`app.on(name, fn)` 用于注册 app 级事件；同一个 `name` 重复注册会替换旧回调。`app.on(name, nil)` 或 `app.on(name)` 用于解绑。退出页面或 app 前建议解绑自己注册的事件。

当前常用事件：

- `app.on("key", function(name, evt_type, evt_code, ts_ms) ... end)`：通用按键事件。`name` 固定为 `"key"`，`evt_type`/`evt_code` 对应 `key` 模块常量。普通按键交互优先用 `key.on()`。
- `app.on("imu", function(name, roll, pitch, gx, gy, gz, ts_ms) ... end)`：IMU 姿态事件。`roll`/`pitch` 单位为度，已做零点校正；当前事件源只推送 `roll`/`pitch`，`gx`/`gy`/`gz` 为预留值，通常是 `0`。

`app.on` 是轻量通用事件通道，同名事件在 Lua 未及时分发前只保留最新一条 pending 数据。回调里不要写长时间阻塞逻辑，高频处理建议只更新状态，耗时工作放到主循环或定时器里。

```lua
app.on("imu", function(_, roll, pitch, gx, gy, gz, ts_ms)
  print("tilt:", roll, pitch, ts_ms)
end)

-- 页面销毁或 app 退出前解绑
app.on("imu", nil)
```

服务和 WebUI 相关接口按需使用：`app.services()`、`app.start_service(id)`、`app.stop_service(id_or_instance)`、`app.route_base()`、`app.set_home_exit(enabled)`。WebUI 是否可用由底层根据当前 app 注册的 `route_base .. "/"` 首页路由自动识别。
`app.start_service(id)` 遇到同 id service 已运行时会重启旧实例。

### sys 设备控制

`sys` 用于设备级状态和简单控制，不建议在高频循环里频繁调整亮度、CPU 频率或 LED。

- 版本和状态：`sys.version()`、`sys.usage()`。
- 屏幕亮度：`sys.setbrightness(level)`、`sys.getbrightness()`。
- CPU 频率：`sys.setcpufreq(mhz)`、`sys.getcpufreq()`。
- RGB LED：`sys.setled(r, g, b)`、`sys.setled("#RRGGBB")`、`sys.setled()`、`sys.getled()`。

### key 按键

`key` 用于当前 Lua app 的物理按键事件。优先用 `key` 模块处理按键。

- `key.on(code, fn)`：监听指定按键，回调参数为 `fn(evt_type, ts_ms)`。
- `key.on(fn)`：监听所有按键，回调参数为 `fn(code, evt_type, ts_ms)`。
- `key.off(code)`：取消指定按键的监听。
- `key.off()`：取消当前 app 注册的全部按键监听。
- `key.off(code, type)`：按事件类型精确解绑，一般脚本很少需要。

按键常量：`key.LEFT`、`key.RIGHT`、`key.UP`、`key.DOWN`、`key.HOME`。
事件常量：`key.START`、`key.SHORT`、`key.LONG_START`、`key.LONG_REPEAT`、`key.LONG_END`、`key.EXIT`。

事件含义：

- `key.START`：按下开始。
- `key.SHORT`：短按释放。
- `key.LONG_START`：长按达到阈值，当前底层阈值约 `800ms`。
- `key.LONG_REPEAT`：长按期间重复触发，当前底层周期约 `200ms`。
- `key.LONG_END`：长按释放。
- `key.EXIT`：系统退出类事件，普通 app 通常不用单独处理。

```lua
key.on(key.LEFT, function(evt_type, ts_ms)
  if evt_type == key.SHORT then
    print("left short", ts_ms)
  elseif evt_type == key.LONG_REPEAT then
    print("left repeat", ts_ms)
  end
end)

key.on(key.HOME, function(evt_type)
  if evt_type == key.SHORT then
    app.exit()
  end
end)
```

### nes

- `nes.start(path[, opts]) -> true|nil, err`
- `nes.stop() -> true`
- `nes.state() -> table`
- `nes.input.set_button(player, button_mask, pressed) -> bool`
- `nes.input.set_mask(player, mask) -> bool`
- `nes.input.clear([player]) -> true`

常量：`nes.PLAYER_1`、`nes.PLAYER_2`、`nes.BTN_A`、`nes.BTN_B`、`nes.BTN_SELECT`、`nes.BTN_START`、`nes.BTN_UP`、`nes.BTN_DOWN`、`nes.BTN_LEFT`、`nes.BTN_RIGHT`。

### 全局辅助函数

- `millis() -> integer`
- `sleep(ms) -> bool`
- `print(...)`
- `lv_lvgl_monitor_reset()`
- `lv_lvgl_monitor_get() -> render_cnt, time_sum_ms, px_sum, last_time_ms, last_px`

### UI

Lua UI 直接使用全局 `lv_*` 函数和 LVGL 常量。控件创建、布局、样式、事件、动画、GIF、canvas 等接口统一查看 `README_LVGL.md`。
