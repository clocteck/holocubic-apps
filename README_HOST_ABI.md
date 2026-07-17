# Host ABI 动态模块接口

Host ABI 用于放在 app `modules/` 目录中的 ESP32-S3 `.so` 动态模块。它让 C/C++
模块直接使用宿主的文件、I2S、任务、Socket、网卡状态和 mDNS 等能力，适合音视频流、
协议栈和其它不应受 Lua 前台调度波动影响的热路径。

ABI 边界只传 C 函数、定长整数、POD 结构和 opaque handle，不传 Arduino C++ 对象。
模块不能直接链接固件内部的 `SD`、`Serial`、LVGL 或 lwIP 符号。

## 头文件和兼容性

唯一准本是固件工程的：

```text
src/dynmod/module_abi.h
```

编译 `.so` 前应把这份头同步到模块工程。普通 app 目录中某些历史示例自带的
`module_abi.h` 可能只包含较早接口，不应据此判断新固件能力。

当前 ABI 版本为 `MODULE_SDK_VERSION == 0x00030000`。函数通过稳定的
`MODULE_PROC_*` ID 逐项解析；`module_host_api_v2` 只是模块本地缓存表，不作为一个
整体结构跨 `.so` 边界传递。因此宿主可以在不改变已有 ID 的前提下追加可选能力。

## 模块目录和加载

部署示例：

```text
/sd/apps/my_app/
├── app.info
├── main.lua
└── modules/
    └── stream.so
```

Lua 当前使用显式绝对路径加载：

```lua
local stream = require("/sd/apps/my_app/modules/stream.so")
```

## 必须导出的入口

每个模块导出以下四个 C 符号：

```c
const module_manifest_t *module_query_v1(void);

int32_t module_create_v2(module_host_resolve_v2_fn resolve,
                         void *resolve_ctx,
                         const module_open_info_t *info,
                         void **out_instance);

int32_t module_luaopen_v1(void *instance, lua_State *L);

void module_destroy_v1(void *instance);
```

生命周期顺序为：

```text
query -> create -> luaopen -> Lua 使用模块 -> destroy -> dlclose
```

- `module_query_v1()` 返回静态 `module_manifest_t`。
- `module_create_v2()` 解析 Host API、分配实例并写入 `out_instance`。
- `module_luaopen_v1()` 成功时返回 `MODULE_OK`，并把模块 table 留在 Lua 栈顶。
- `module_destroy_v1()` 停任务、关连接、注销 mDNS/BLE、释放实例；返回后不能再执行模块代码。

最小骨架：

```c
#include "module_abi.h"

typedef struct demo_instance_t {
    module_host_api_v2 host;
} demo_instance_t;

static const module_manifest_t manifest = {
    MODULE_MANIFEST_MAGIC,
    MODULE_SDK_VERSION,
    sizeof(module_manifest_t),
    "demo",
    "0.1.0",
    "Host ABI demo",
    0,
    MODULE_BOOTSTRAP_ABI_VERSION,
};

const module_manifest_t *module_query_v1(void)
{
    return &manifest;
}

int32_t module_create_v2(module_host_resolve_v2_fn resolve,
                         void *resolve_ctx,
                         const module_open_info_t *info,
                         void **out_instance)
{
    demo_instance_t *instance;
    module_host_api_v2 host;
    int32_t err;
    (void)info;

    if (!resolve || !out_instance) return MODULE_ERR_INVALID_ARG;
    *out_instance = NULL;

    err = module_sdk_resolve_host_v2(resolve, resolve_ctx, &host);
    if (err != MODULE_OK) return err;

    instance = (demo_instance_t *)host.heap.calloc(
        1, sizeof(*instance), MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT);
    if (!instance) return MODULE_ERR_NO_MEMORY;

    instance->host = host;
    *out_instance = instance;
    return MODULE_OK;
}
```

网络、BLE、目录和同步分组是 optional。解析成功不代表每个可选函数都存在，使用前要
检查函数指针：

```c
if (!instance->host.socket.open || !instance->host.socket.poll) {
    return MODULE_ERR_UNSUPPORTED;
}
```

## Host API 分组

| 分组 | 接口 | 说明 |
| --- | --- | --- |
| `serial` | `write/print/println/flush` | 串口日志和二进制输出 |
| `sd` | `begin/mounted/mount_point/exists/mkdir/remove/rename/open` | SD 文件系统入口 |
| `file` | `close/available/read/write/seek/position/size_bytes/flush/is_directory` | opaque 文件句柄 |
| `display` | `width/height/get_caps/acquire/release/startWrite/pushImageDMA/endWrite/fillScreen/setAddrWindow/pushPixelsDMA` | 独占式 RGB565 直出，不是 LVGL |
| `audio` | `begin/write/available/end` | 已预留，当前真实 PCM bridge 未接通 |
| `time` | `millis/micros/delay/yield` | 时间和任务让出 |
| `heap` | `malloc/calloc/realloc/free/free_size/largest_free_block` | 可指定 Internal、PSRAM、DMA 等能力 |
| `task` | `create/remove/yield/delay/create_ex` | 宿主管理的模块任务 |
| `lua` | `gettop/settop/type`、check/push、table/global、registry、closure、userdata 等 | 在 `luaopen` 中注册 Lua table；`newuserdata` 为 optional |
| `i2s` | `begin/write/read/availableForWrite/flush/mute/end` | 音频输入输出 |
| `diag` | `update_context/set_rom_path/heartbeat` | 崩溃后诊断上下文 |
| `dir` | `open/open_next/name/path/is_dir/size_bytes/close` | optional 目录遍历 |
| `ble` | `open/close`、`gap_*`、`gattc_*`、`event_poll` | optional；只授权后台 Service |
| `sync` | `create_counting/create_mutex/take/give/destroy` | optional opaque 同步对象 |
| `socket` | `open/bind/listen/accept/connect/recv/recvfrom/send/sendto/poll/setsockopt/getsockname/shutdown/close` | optional IPv4 TCP/UDP |
| `netif` | `get_snapshot/wait_event` | optional 网卡快照和无竞态事件等待 |
| `mdns` | `service_register/service_update_txt/service_unregister` | optional 服务发布 |

具体原型、结构和常量以同步到模块工程的 `module_abi.h` 为准。以下重点说明新增的网络
接口及容易出错的生命周期规则。

## Socket API

Socket API 是阻塞式 IPv4 API，设计给模块通过 `host->task.create/create_ex()` 创建的
worker task 使用，不建议在 `module_luaopen_v1()` 或 Lua 回调栈里长时间阻塞。

```c
int32_t open(uint32_t type, module_socket_handle_t *out_socket);
int32_t bind(module_socket_handle_t socket, const module_socket_addr_t *local_addr);
int32_t listen(module_socket_handle_t socket, uint32_t backlog);
int32_t accept(module_socket_handle_t listener,
               module_socket_handle_t *out_socket,
               module_socket_addr_t *out_peer_addr);
int32_t connect(module_socket_handle_t socket, const module_socket_addr_t *peer_addr);
int32_t recv(module_socket_handle_t socket, void *buf, size_t capacity,
             size_t *out_received);
int32_t recvfrom(module_socket_handle_t socket, void *buf, size_t capacity,
                 size_t *out_received, module_socket_addr_t *out_peer_addr);
int32_t send(module_socket_handle_t socket, const void *data, size_t len,
             size_t *out_sent);
int32_t sendto(module_socket_handle_t socket, const void *data, size_t len,
               const module_socket_addr_t *peer_addr, size_t *out_sent);
int32_t poll(module_socket_poll_item_t *items, size_t count,
             uint32_t timeout_ms, size_t *out_ready);
int32_t setsockopt(module_socket_handle_t socket, uint32_t option, int32_t value);
int32_t getsockname(module_socket_handle_t socket,
                    module_socket_addr_t *out_local_addr);
int32_t shutdown(module_socket_handle_t socket, uint32_t how);
int32_t close(module_socket_handle_t socket);
```

### 类型和地址

```c
MODULE_SOCKET_TYPE_STREAM       /* TCP */
MODULE_SOCKET_TYPE_DGRAM        /* UDP */
MODULE_SOCKET_INVALID           /* -1 */
```

`module_socket_addr_t.address[4]` 按点分十进制顺序保存，例如 `192.168.1.20` 为
`{192, 168, 1, 20}`；`port` 使用宿主字节序，不需要 `htons()`。所有带 `size` 的 ABI
结构都先清零并填写 `size = sizeof(struct)`：

```c
module_socket_addr_t peer = {0};
peer.size = sizeof(peer);
peer.address[0] = 192;
peer.address[1] = 168;
peer.address[2] = 1;
peer.address[3] = 20;
peer.port = 7000;
```

当前接口只接收数值 IPv4 地址，不包含 DNS 域名解析接口。

### poll 事件

```c
MODULE_SOCKET_POLL_READ
MODULE_SOCKET_POLL_WRITE
MODULE_SOCKET_POLL_ERROR
MODULE_SOCKET_POLL_HANGUP
```

每个 `module_socket_poll_item_t` 都要填写 `size/socket/events`，宿主写回 `revents`。
超时不是错误：`poll()` 返回 `MODULE_OK`，同时 `out_ready == 0`。`count` 不能超过当前
固件的 lwIP socket 上限，模块不应写死一个更大的数组数量。

### Socket options

```c
MODULE_SOCKET_OPT_REUSE_ADDR
MODULE_SOCKET_OPT_BROADCAST
MODULE_SOCKET_OPT_KEEP_ALIVE
MODULE_SOCKET_OPT_TCP_NO_DELAY
MODULE_SOCKET_OPT_RECV_TIMEOUT_MS
MODULE_SOCKET_OPT_SEND_TIMEOUT_MS
```

`setsockopt()` 的 `value` 对布尔项使用 `0/1`，超时项使用毫秒。关闭方向使用
`MODULE_SOCKET_SHUTDOWN_READ/WRITE/BOTH`。

### 收发约定

- `send/sendto` 允许部分发送；成功时按 `out_sent` 前移指针并循环，不能假设一次发完。
- TCP `recv()` 返回 `MODULE_OK` 且 `out_received == 0` 表示对端有序关闭。
- 调用期间 buffer 只是借给宿主，调用返回后宿主不再保留指针。
- 任何路径都要关闭已创建的 socket；需要唤醒阻塞 worker 时可先 `shutdown()` 再 `close()`。

发送完整缓冲区的典型写法：

```c
static int32_t send_all(const module_socket_api_t *socket_api,
                        module_socket_handle_t socket,
                        const uint8_t *data,
                        size_t len)
{
    size_t offset = 0;
    while (offset < len) {
        size_t sent = 0;
        int32_t err = socket_api->send(socket, data + offset, len - offset, &sent);
        if (err != MODULE_OK) return err;
        if (sent == 0) return MODULE_ERR_IO;
        offset += sent;
    }
    return MODULE_OK;
}
```

## Netif API

原来分散的 `get_state/get_ipv4/get_mac/get_link_generation` 合并为一次原子快照，减少
调用数，并避免分别读取时状态已经变化：

```c
int32_t get_snapshot(uint32_t netif, module_netif_snapshot_t *out_snapshot);

int32_t wait_event(uint32_t netif,
                   uint32_t observed_generation,
                   uint32_t timeout_ms,
                   module_netif_snapshot_t *out_snapshot);
```

网卡：

```c
MODULE_NETIF_DEFAULT
MODULE_NETIF_WIFI_STA
MODULE_NETIF_WIFI_AP
```

`snapshot.state` 是以下位的组合：

```c
MODULE_NETIF_STATE_STARTED
MODULE_NETIF_STATE_LINK_UP
MODULE_NETIF_STATE_IPV4_READY
```

正确的无竞态等待顺序：

```c
module_netif_snapshot_t snapshot = {0};
snapshot.size = sizeof(snapshot);

int32_t err = host->netif.get_snapshot(MODULE_NETIF_WIFI_STA, &snapshot);
while (err == MODULE_OK && running) {
    uint32_t generation = snapshot.generation;

    if (snapshot.state & MODULE_NETIF_STATE_IPV4_READY) {
        /* 使用 snapshot.ipv4 和 snapshot.mac。 */
    }

    snapshot.size = sizeof(snapshot);
    err = host->netif.wait_event(MODULE_NETIF_WIFI_STA,
                                 generation,
                                 10000,
                                 &snapshot);
    if (err == MODULE_ERR_BUSY) {
        err = MODULE_OK; /* 仅超时，可继续检查停止标志。 */
    }
}
```

如果 `observed_generation` 已过期，`wait_event()` 立即返回最新快照；否则等待下一次
启动、链路或 IPv4 变化。超时返回 `MODULE_ERR_BUSY`，`MODULE_WAIT_FOREVER` 表示无限等待。

## mDNS API

```c
int32_t service_register(const char *instance,
                         const char *service_type,
                         const char *protocol,
                         uint16_t port,
                         const module_mdns_txt_record_t *txt_records,
                         size_t txt_count,
                         module_mdns_service_handle_t *out_handle);

int32_t service_update_txt(module_mdns_service_handle_t handle,
                           const module_mdns_txt_record_t *txt_records,
                           size_t txt_count);

int32_t service_unregister(module_mdns_service_handle_t handle);
```

RAOP 示例：

```c
module_mdns_txt_record_t txt[] = {
    {"txtvers", "1"},
    {"ch", "2"},
};
module_mdns_service_handle_t handle = NULL;

int32_t err = host->mdns.service_register("Cubic Player",
                                           "_raop",
                                           "_tcp",
                                           7000,
                                           txt,
                                           sizeof(txt) / sizeof(txt[0]),
                                           &handle);
```

`register/update_txt` 会在返回前复制 instance、service、protocol、key 和 value，模块可在
调用后释放临时字符串。handle 是宿主对象，只能传回 update/unregister；模块销毁前必须
注销。资源不足或系统 mDNS 不可用时会返回对应错误码，不能假设注册必然成功。

## 内存、任务和卸载

常用 heap capability：

```c
MODULE_HEAP_DEFAULT
MODULE_HEAP_INTERNAL
MODULE_HEAP_PSRAM
MODULE_HEAP_DMA
MODULE_HEAP_EXEC
MODULE_HEAP_8BIT
MODULE_HEAP_32BIT
```

- 大块网络/解码缓冲优先 `MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT`。
- DMA buffer 使用 `MODULE_HEAP_INTERNAL | MODULE_HEAP_DMA | MODULE_HEAP_8BIT`。
- 通过 Host 分配的内存应通过同一 Host API 释放。
- 后台任务必须由 `host->task` 创建并登记归属。模块代码还在任务中执行时，宿主不会安全卸载 `.so`。
- `module_destroy_v1()` 先置停止标志并唤醒阻塞调用，再等待/删除任务，最后释放 socket、文件、mDNS、BLE、同步对象和实例内存。

## BLE 和 Display 限制

BLE 资源按 owner 授权。只有后台 Service 加载模块时，`module_open_info_t.owner_token`
才可能非零；普通前台 app 的模块不能打开 BLE session。BLE 回调数据通过固定事件队列
交给模块自己的 `event_poll()`，不要让宿主保存模块函数指针作为异步回调。

`display` 是绕开 LVGL 的独占式高频 RGB565 输出接口，只适合明确接管显示的模块。
当前不支持通用像素格式、带 stride 的任意图像和完整的 `fillScreen` 颜色能力。普通 app
界面仍使用 Lua LVGL；后台浮层使用 `service_ui`。

## 错误码

| 错误码 | 含义 |
| --- | --- |
| `MODULE_OK` | 成功 |
| `MODULE_ERR_FAILED` | 未分类失败 |
| `MODULE_ERR_INVALID_ARG` | 参数或结构 `size` 无效 |
| `MODULE_ERR_NO_MEMORY` | 内存/固定资源不足 |
| `MODULE_ERR_NOT_FOUND` | 目标不存在 |
| `MODULE_ERR_UNSUPPORTED` | 当前宿主没有此 optional 能力 |
| `MODULE_ERR_BUSY` | 资源忙或等待超时 |
| `MODULE_ERR_IO` | I/O 失败 |
| `MODULE_ERR_BAD_STATE` | 生命周期/状态不允许当前操作 |
| `MODULE_ERR_VERSION` | ABI 版本不兼容 |

未使用的 Host ABI 函数不会主动运行，也不会产生持续 CPU 开销。只有加载模块时解析并保存
函数指针会增加少量实例内存；Socket、netif 事件和 mDNS 等资源在模块实际调用对应接口后
才创建。是否有后台消耗最终取决于模块自己是否创建任务、定时器、连接或注册服务。
