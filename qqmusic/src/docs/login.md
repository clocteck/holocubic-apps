# QQ / 微信扫码协议与边界

这是 Cubic 的非官方 QQ 音乐客户端。协议直接请求平台 HTTPS 服务，不经过第三方 API 代理。

## QQ

1. ptqrshow 获取 PNG 和 qrsig；qrsig 仅存于内存。
2. ptqrlogin 使用 hash33(qrsig) 轮询：66 等待、67 待确认、65 过期、0 已授权。
3. 提取 uin / ptsigx，在固定 check_sig 域名交换短期 Cookie。
4. graph.qq.com/oauth2.0/authorize 返回授权 code；验证固定回调域名和随机 state。
5. QQConnectLogin.LoginServer.QQLogin 交换音乐凭据并存入 /sd/data/qqmusic/session.json。

### 2026-09-16 QQ 授权兼容修复

- `login.lua` 的 `auth_time` 和轮询 `action` 改用 `time.get()` 的 Unix 时间，
  不再发送应用启动后的毫秒计数。秒/毫秒分段拼接为十进制字符串，避免设备
  32 位整数溢出或浮点精度损失；未校时明确提示，不发送错误时间。
- `ui` 使用独立 UUID 格式标识，`state` 每次授权独立生成；仍校验当前授权状态。
- `ptsigx` 按完整查询参数提取、解码再编码发送，避免 `%w` 正则截断符号。
- `provider.lua` 逐条解析多值 Set-Cookie，按目标 `graph.qq.com` 选取域名更具体的同名
  Cookie，拒绝其他域；根域清理 Cookie 不再覆盖子域凭据，同域清理仍然生效。
- OAuth 回调先拆分查询参数再解码一次，完整提取授权码，拒绝重复参数、
  非 HTTPS / 非精确回调路径、缺失或不匹配的 state。不跟随 Location。
- 登录兑换 RPC 使用匿名上下文，不夹带之前保存的微信/QQ Cookie、authst 或账号。
  成功取得并保存新凭据之前保留原会话，取消/失败不覆盖原账号。
- `/qqmusic/status.login_diagnostics` 仅输出 revision、stage、固定 reason、HTTP 状态、
  Cookie 条目/空值计数及凭据是否存在；
  不输出 state、code、Cookie、完整 Location。

旧设备观测：`qr_authorize` 返回 302，但统一报“QQ授权未完成或状态不匹配”。
旧日志未保留具体分支，不能据此认定某一个参数就是此次现场失败的唯一原因。
回归测试覆盖完整 QQ 兑换、编码回调、错误状态/地址/重复字段、取消、旧会话隔离、
签名完整性、Cookie 域名选择、未校时及微信登录。

第一轮实机扫码（诊断 revision 2）：302 `qr_exchange` 的 `p_skey` 缺失或为空，
未进入音乐凭据兑换；失败后原微信会话仍保留。revision 3 补充无凭据的 Cookie
计数诊断并修复上述域名覆盖/签名截断问题。

第二轮实机扫码（revision 3）成功：`login_status=done`、`login_mode=qq`、
`account.login_type=2`，进入收藏歌单；check_sig 与 authorize 均返回 302。
安全诊断记录为 `cookie_lines=11`、`p_skey_candidates=2`、`p_skey_empty=1`、
`p_skey_usable=true`，与“同名跨域空 Cookie 覆盖有效凭据”回归用例一致。
30 项 Python/Lua 测试、网页回归及动态模块构建均通过；login.lua/provider.lua/web.lua
已上传设备并逐个 SHA-256 校验；此轮实机验证时版本为 1.0.0，未推送云端。

后续 1.0.1 发布包含以上修复，package 与 src 同步交付；清单、说明页、User-Agent
及原生模块版本统一升级，30 项应用测试、网页回归、原生内存测试与构建全部通过。
本次版本发布不重新启动设备或改动已登录账号。

## 微信

1. open.weixin.qq.com/connect/qrconnect 获取 UUID。
2. connect/qrcode/<UUID> 获取 JPEG（线上测得 470×470，约 47KiB）；设备缩放至 154px 区域。
3. lp.open.weixin.qq.com/connect/l/qrconnect 长轮询：408 等待、404 已扫码、405 已确认。
4. music.login.LoginServer.Login 使用 code / strAppid 交换音乐凭据，tmeLoginType=1。

两者必须分别生成二维码；左右键切换，短按 Home 跳过，长按退出。
刷新通过网页按钮，或左右切换回原方式。切换会取消旧请求并使旧回调失效。
首版不实现 QQ 音乐 App 本身的 MQTT-over-WebSocket 扫码，按用户要求暂缓。

## 安全与验证

- 不执行服务端 JavaScript；只解析固定回调字段。
- 不自动跟随授权重定向；凭据只发送到对应固定平台域名。
- 不在日志、状态接口或网页中输出 Cookie、UUID、qrsig、code 或签名播放 URL。
- 二维码本身是短期授权信息，仅显示于用户设备/局域网控制页。
- 会话在 SD 卡是明文，设备接口没有公网账号认证；只用于可信局域网。
- 恢复的是已保存会话，最终有效性仍由平台接口判断；不承诺永不过期。
- 扫码后最终凭据交换必须由用户手机确认后做实机验收，不以取码成功代替登录成功。

## 参考源码（仅核对协议字段，Lua 状态机自行实现）

- https://github.com/L-1124/QQMusicApi/blob/main/qqmusic_api/modules/login.py
- https://github.com/L-1124/QQMusicApi/blob/main/qqmusic_api/models/request.py
- https://github.com/L-1124/QQMusicApi/blob/main/qqmusic_api/modules/user.py
- https://github.com/jsososo/QQMusicApi/blob/master/routes/recommend.js

上游是非官方协议研究，不代表腾讯提供稳定、公开的 API 合约。
