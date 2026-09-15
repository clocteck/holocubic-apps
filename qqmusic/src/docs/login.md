# QQ / 微信扫码协议与边界

这是 Cubic 的非官方 QQ 音乐客户端。协议直接请求平台 HTTPS 服务，不经过第三方 API 代理。

## QQ

1. ptqrshow 获取 PNG 和 qrsig；qrsig 仅存于内存。
2. ptqrlogin 使用 hash33(qrsig) 轮询：66 等待、67 待确认、65 过期、0 已授权。
3. 提取 uin / ptsigx，在固定 check_sig 域名交换短期 Cookie。
4. graph.qq.com/oauth2.0/authorize 返回授权 code；验证固定回调域名和随机 state。
5. QQConnectLogin.LoginServer.QQLogin 交换音乐凭据并存入 /sd/data/qqmusic/session.json。

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
