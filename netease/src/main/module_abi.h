#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct lua_State lua_State;

typedef int (*module_lua_cfunction_t)(lua_State *L);

#define MODULE_BOOTSTRAP_ABI_VERSION 1u
#define MODULE_SDK_VERSION 0x00030000u
#define MODULE_ABI_VERSION MODULE_SDK_VERSION
#define MODULE_MANIFEST_MAGIC 0x414D4F44u /* "AMOD" */
#define MODULE_NAME_MAX 32u
#define MODULE_PATH_MAX 160u

#define MODULE_SYMBOL_QUERY_V1 "module_query_v1"
#define MODULE_SYMBOL_CREATE_V2 "module_create_v2"
#define MODULE_SYMBOL_LUAOPEN_V1 "module_luaopen_v1"
#define MODULE_SYMBOL_DESTROY_V1 "module_destroy_v1"

#define MODULE_PROC_SERIAL_WRITE_V1 0x00010001u
#define MODULE_PROC_SERIAL_PRINT_V1 0x00010002u
#define MODULE_PROC_SERIAL_PRINTLN_V1 0x00010003u
#define MODULE_PROC_SERIAL_FLUSH_V1 0x00010004u

#define MODULE_PROC_SD_BEGIN_V1 0x00020001u
#define MODULE_PROC_SD_MOUNTED_V1 0x00020002u
#define MODULE_PROC_SD_MOUNT_POINT_V1 0x00020003u
#define MODULE_PROC_SD_EXISTS_V1 0x00020004u
#define MODULE_PROC_SD_MKDIR_V1 0x00020005u
#define MODULE_PROC_SD_REMOVE_V1 0x00020006u
#define MODULE_PROC_SD_RENAME_V1 0x00020007u
#define MODULE_PROC_SD_OPEN_V1 0x00020008u

#define MODULE_PROC_FILE_CLOSE_V1 0x00030001u
#define MODULE_PROC_FILE_AVAILABLE_V1 0x00030002u
#define MODULE_PROC_FILE_READ_V1 0x00030003u
#define MODULE_PROC_FILE_WRITE_V1 0x00030004u
#define MODULE_PROC_FILE_SEEK_V1 0x00030005u
#define MODULE_PROC_FILE_POSITION_V1 0x00030006u
#define MODULE_PROC_FILE_SIZE_BYTES_V1 0x00030007u
#define MODULE_PROC_FILE_FLUSH_V1 0x00030008u
#define MODULE_PROC_FILE_IS_DIRECTORY_V1 0x00030009u

#define MODULE_PROC_DISPLAY_WIDTH_V1 0x00040001u
#define MODULE_PROC_DISPLAY_HEIGHT_V1 0x00040002u
#define MODULE_PROC_DISPLAY_GET_CAPS_V1 0x00040003u
#define MODULE_PROC_DISPLAY_ACQUIRE_V1 0x00040004u
#define MODULE_PROC_DISPLAY_RELEASE_V1 0x00040005u
#define MODULE_PROC_DISPLAY_START_WRITE_V1 0x00040006u
#define MODULE_PROC_DISPLAY_PUSH_IMAGE_DMA_V1 0x00040007u
#define MODULE_PROC_DISPLAY_END_WRITE_V1 0x00040008u
#define MODULE_PROC_DISPLAY_FILL_SCREEN_V1 0x00040009u
#define MODULE_PROC_DISPLAY_SET_ADDR_WINDOW_V1 0x0004000Au
#define MODULE_PROC_DISPLAY_PUSH_PIXELS_DMA_V1 0x0004000Bu
#define MODULE_PROC_DISPLAY_TRY_PUSH_PIXELS_DMA_V1 0x0004000Cu
#define MODULE_PROC_DISPLAY_DMA_BUSY_V1 0x0004000Du

#define MODULE_PROC_IMU_READ_RAW_V1 0x00130001u

// tryPushPixelsDMA: internal DMA RAM, 4-byte aligned, even pixel count.
#define MODULE_DISPLAY_TRY_DMA_MAX_PIXELS_V1 16384u

#define MODULE_PROC_AUDIO_BEGIN_V1 0x00050001u
#define MODULE_PROC_AUDIO_WRITE_V1 0x00050002u
#define MODULE_PROC_AUDIO_AVAILABLE_V1 0x00050003u
#define MODULE_PROC_AUDIO_END_V1 0x00050004u

#define MODULE_PROC_TIME_MILLIS_V1 0x00060001u
#define MODULE_PROC_TIME_MICROS_V1 0x00060002u
#define MODULE_PROC_TIME_DELAY_V1 0x00060003u
#define MODULE_PROC_TIME_YIELD_V1 0x00060004u

#define MODULE_PROC_HEAP_MALLOC_V1 0x00070001u
#define MODULE_PROC_HEAP_CALLOC_V1 0x00070002u
#define MODULE_PROC_HEAP_REALLOC_V1 0x00070003u
#define MODULE_PROC_HEAP_FREE_V1 0x00070004u
#define MODULE_PROC_HEAP_FREE_SIZE_V1 0x00070005u
#define MODULE_PROC_HEAP_LARGEST_FREE_BLOCK_V1 0x00070006u

#define MODULE_PROC_TASK_CREATE_V1 0x00080001u
#define MODULE_PROC_TASK_REMOVE_V1 0x00080002u
#define MODULE_PROC_TASK_YIELD_V1 0x00080003u
#define MODULE_PROC_TASK_DELAY_V1 0x00080004u
#define MODULE_PROC_TASK_CREATE_EX_V1 0x00080005u

#define MODULE_PROC_LUA_GETTOP_V1 0x00090001u
#define MODULE_PROC_LUA_SETTOP_V1 0x00090002u
#define MODULE_PROC_LUA_TYPE_V1 0x00090003u
#define MODULE_PROC_LUA_ISTABLE_V1 0x00090004u
#define MODULE_PROC_LUA_ISNIL_V1 0x00090005u
#define MODULE_PROC_LUA_ISNUMBER_V1 0x00090006u
#define MODULE_PROC_LUA_ISSTRING_V1 0x00090007u
#define MODULE_PROC_LUA_TOBOOLEAN_V1 0x00090008u
#define MODULE_PROC_LUA_TOINTEGER_V1 0x00090009u
#define MODULE_PROC_LUA_TONUMBER_V1 0x0009000Au
#define MODULE_PROC_LUA_TOSTRING_V1 0x0009000Bu
#define MODULE_PROC_LUA_CHECKINTEGER_V1 0x0009000Cu
#define MODULE_PROC_LUA_CHECKNUMBER_V1 0x0009000Du
#define MODULE_PROC_LUA_CHECKSTRING_V1 0x0009000Eu
#define MODULE_PROC_LUA_TOUSERDATA_V1 0x0009000Fu
#define MODULE_PROC_LUA_PUSHNIL_V1 0x00090010u
#define MODULE_PROC_LUA_PUSHBOOLEAN_V1 0x00090011u
#define MODULE_PROC_LUA_PUSHINTEGER_V1 0x00090012u
#define MODULE_PROC_LUA_PUSHNUMBER_V1 0x00090013u
#define MODULE_PROC_LUA_PUSHSTRING_V1 0x00090014u
#define MODULE_PROC_LUA_PUSHLIGHTUSERDATA_V1 0x00090015u
#define MODULE_PROC_LUA_PUSHCFUNCTION_V1 0x00090016u
#define MODULE_PROC_LUA_PUSHCCLOSURE_V1 0x00090017u
#define MODULE_PROC_LUA_PUSHVALUE_V1 0x00090018u
#define MODULE_PROC_LUA_NEWTABLE_V1 0x00090019u
#define MODULE_PROC_LUA_CREATETABLE_V1 0x0009001Au
#define MODULE_PROC_LUA_GETFIELD_V1 0x0009001Bu
#define MODULE_PROC_LUA_SETFIELD_V1 0x0009001Cu
#define MODULE_PROC_LUA_GETGLOBAL_V1 0x0009001Du
#define MODULE_PROC_LUA_SETGLOBAL_V1 0x0009001Eu
#define MODULE_PROC_LUA_REGISTRY_REF_V1 0x0009001Fu
#define MODULE_PROC_LUA_REGISTRY_UNREF_V1 0x00090020u
#define MODULE_PROC_LUA_REGISTRY_RAWGETI_V1 0x00090021u
#define MODULE_PROC_LUA_UPVALUE_INDEX_V1 0x00090022u
#define MODULE_PROC_LUA_ERROR_V1 0x00090023u
#define MODULE_PROC_LUA_TOLSTRING_V1 0x00090024u
#define MODULE_PROC_LUA_CHECKLSTRING_V1 0x00090025u
#define MODULE_PROC_LUA_PUSHLSTRING_V1 0x00090026u
#define MODULE_PROC_LUA_NEWUSERDATA_V1 0x00090027u

#define MODULE_PROC_I2S_BEGIN_V1 0x000A0001u
#define MODULE_PROC_I2S_WRITE_V1 0x000A0002u
#define MODULE_PROC_I2S_READ_V1 0x000A0003u
#define MODULE_PROC_I2S_AVAILABLE_FOR_WRITE_V1 0x000A0004u
#define MODULE_PROC_I2S_FLUSH_V1 0x000A0005u
#define MODULE_PROC_I2S_MUTE_V1 0x000A0006u
#define MODULE_PROC_I2S_END_V1 0x000A0007u

#define MODULE_PROC_DIAG_UPDATE_CONTEXT_V1 0x000B0001u
#define MODULE_PROC_DIAG_SET_ROM_PATH_V1 0x000B0002u
#define MODULE_PROC_DIAG_HEARTBEAT_V1 0x000B0003u

#define MODULE_PROC_DIR_OPEN_V2 0x000C0001u
#define MODULE_PROC_DIR_OPEN_NEXT_V2 0x000C0002u
#define MODULE_PROC_DIR_NAME_V2 0x000C0003u
#define MODULE_PROC_DIR_PATH_V2 0x000C0004u
#define MODULE_PROC_DIR_IS_DIR_V2 0x000C0005u
#define MODULE_PROC_DIR_SIZE_BYTES_V2 0x000C0006u
#define MODULE_PROC_DIR_CLOSE_V2 0x000C0007u

/* BLE central transport. All operations are asynchronous unless documented otherwise. */
#define MODULE_PROC_BLE_OPEN_V1 0x000D0001u
#define MODULE_PROC_BLE_CLOSE_V1 0x000D0002u
#define MODULE_PROC_BLE_GAP_SCAN_V1 0x000D0003u
#define MODULE_PROC_BLE_GAP_SCAN_STOP_V1 0x000D0004u
#define MODULE_PROC_BLE_GAP_CONNECT_V1 0x000D0005u
#define MODULE_PROC_BLE_GAP_DISCONNECT_V1 0x000D0006u
#define MODULE_PROC_BLE_GAP_PAIR_V1 0x000D0007u
#define MODULE_PROC_BLE_GATTC_DISCOVER_SERVICES_V1 0x000D0008u
#define MODULE_PROC_BLE_GATTC_DISCOVER_CHARACTERISTICS_V1 0x000D0009u
#define MODULE_PROC_BLE_GATTC_READ_V1 0x000D000Au
#define MODULE_PROC_BLE_GATTC_WRITE_V1 0x000D000Bu
#define MODULE_PROC_BLE_GATTC_EXCHANGE_MTU_V1 0x000D000Cu
#define MODULE_PROC_BLE_EVENT_POLL_V1 0x000D000Du
#define MODULE_PROC_BLE_GATTC_DISCOVER_DESCRIPTORS_V1 0x000D000Eu
#define MODULE_PROC_BLE_GAP_SET_CONNECTION_PARAMS_V1 0x000D000Fu
#define MODULE_PROC_BLE_GAP_FORGET_DEVICE_V1 0x000D0010u
#define MODULE_PROC_BLE_GAP_CLEAR_BONDS_V1 0x000D0011u
#define MODULE_PROC_BLE_GATTC_READ_LONG_V1 0x000D0012u
#define MODULE_PROC_BLE_GATTC_WRITE_LONG_V1 0x000D0013u
#define MODULE_PROC_BLE_GAP_GET_RSSI_V1 0x000D0014u

#define MODULE_PROC_SYNC_CREATE_COUNTING_V1 0x000E0001u
#define MODULE_PROC_SYNC_CREATE_MUTEX_V1 0x000E0002u
#define MODULE_PROC_SYNC_TAKE_V1 0x000E0003u
#define MODULE_PROC_SYNC_GIVE_V1 0x000E0004u
#define MODULE_PROC_SYNC_DESTROY_V1 0x000E0005u

/* IPv4 socket transport. The ABI does not expose lwIP/POSIX types or constants. */
#define MODULE_PROC_SOCKET_OPEN_V1 0x000F0001u
#define MODULE_PROC_SOCKET_BIND_V1 0x000F0002u
#define MODULE_PROC_SOCKET_LISTEN_V1 0x000F0003u
#define MODULE_PROC_SOCKET_ACCEPT_V1 0x000F0004u
#define MODULE_PROC_SOCKET_CONNECT_V1 0x000F0005u
#define MODULE_PROC_SOCKET_RECV_V1 0x000F0006u
#define MODULE_PROC_SOCKET_RECVFROM_V1 0x000F0007u
#define MODULE_PROC_SOCKET_SEND_V1 0x000F0008u
#define MODULE_PROC_SOCKET_SENDTO_V1 0x000F0009u
#define MODULE_PROC_SOCKET_POLL_V1 0x000F000Au
#define MODULE_PROC_SOCKET_SETSOCKOPT_V1 0x000F000Bu
#define MODULE_PROC_SOCKET_GETSOCKNAME_V1 0x000F000Cu
#define MODULE_PROC_SOCKET_SHUTDOWN_V1 0x000F000Du
#define MODULE_PROC_SOCKET_CLOSE_V1 0x000F000Eu

#define MODULE_PROC_NETIF_GET_SNAPSHOT_V1 0x00100001u
#define MODULE_PROC_NETIF_WAIT_EVENT_V1 0x00100002u

#define MODULE_PROC_MDNS_SERVICE_REGISTER_V1 0x00110001u
#define MODULE_PROC_MDNS_SERVICE_UPDATE_TXT_V1 0x00110002u
#define MODULE_PROC_MDNS_SERVICE_UNREGISTER_V1 0x00110003u

/* Coalesced module-worker -> owning Lua runtime dispatch. */
#define MODULE_PROC_RUNTIME_EVENT_POST_V1 0x00120001u
#define MODULE_PROC_RUNTIME_EVENT_CANCEL_V1 0x00120002u

#define DYNMOD_LAST_CONTEXT_MAGIC 0x4D4F4443u /* "MODC" */
#define DYNMOD_LAST_CONTEXT_VERSION 1u
#define DYNMOD_LAST_MODULE_PATH_MAX 128u
#define DYNMOD_LAST_ROM_PATH_MAX 160u

typedef struct dynmod_last_context_t {
    uint32_t magic;
    uint32_t version;

    char module_name[MODULE_NAME_MAX];
    char module_path[DYNMOD_LAST_MODULE_PATH_MAX];
    char rom_path[DYNMOD_LAST_ROM_PATH_MAX];

    uintptr_t text_start;
    uintptr_t text_end;
    uintptr_t data_start;
    uintptr_t data_end;
    uintptr_t psram_start;
    uintptr_t psram_end;

    uint32_t mapper;
    uint32_t frame;
    uint32_t scanline;
    uint16_t cpu_pc;
    uint8_t cpu_a;
    uint8_t cpu_x;
    uint8_t cpu_y;
    uint8_t cpu_p;
    uint8_t cpu_sp;

    uint32_t heartbeat_ms;
} dynmod_last_context_t;

typedef enum module_error_t {
    MODULE_OK = 0,
    MODULE_ERR_FAILED = -1,
    MODULE_ERR_INVALID_ARG = -2,
    MODULE_ERR_NO_MEMORY = -3,
    MODULE_ERR_NOT_FOUND = -4,
    MODULE_ERR_UNSUPPORTED = -5,
    MODULE_ERR_BUSY = -6,
    MODULE_ERR_IO = -7,
    MODULE_ERR_BAD_STATE = -8,
    MODULE_ERR_VERSION = -9,
} module_error_t;

#define MODULE_WAIT_FOREVER UINT32_MAX

typedef enum module_heap_caps_t {
    MODULE_HEAP_DEFAULT = 0,
    MODULE_HEAP_INTERNAL = 1u << 0,
    MODULE_HEAP_PSRAM = 1u << 1,
    MODULE_HEAP_DMA = 1u << 2,
    MODULE_HEAP_EXEC = 1u << 3,
    MODULE_HEAP_8BIT = 1u << 4,
    MODULE_HEAP_32BIT = 1u << 5,
} module_heap_caps_t;

typedef enum module_file_mode_t {
    MODULE_FILE_READ = 1u << 0,
    MODULE_FILE_WRITE = 1u << 1,
    MODULE_FILE_APPEND = 1u << 2,
    MODULE_FILE_CREATE = 1u << 3,
    MODULE_FILE_TRUNC = 1u << 4,
} module_file_mode_t;

typedef enum module_seek_mode_t {
    MODULE_SEEK_SET = 0,
    MODULE_SEEK_CUR = 1,
    MODULE_SEEK_END = 2,
} module_seek_mode_t;

typedef enum module_pixel_format_t {
    MODULE_PIXEL_RGB565 = 1,
} module_pixel_format_t;

typedef enum module_i2s_mode_t {
    MODULE_I2S_MODE_TX = 1u << 0,
    MODULE_I2S_MODE_RX = 1u << 1,
    MODULE_I2S_MODE_TX_RX = MODULE_I2S_MODE_TX | MODULE_I2S_MODE_RX,
} module_i2s_mode_t;

typedef enum module_i2s_format_t {
    MODULE_I2S_FORMAT_I2S = 1,
    MODULE_I2S_FORMAT_LEFT = 2,
    MODULE_I2S_FORMAT_PCM_SHORT = 3,
    MODULE_I2S_FORMAT_PCM_LONG = 4,
} module_i2s_format_t;

typedef enum module_i2s_channel_mode_t {
    MODULE_I2S_CHANNEL_STEREO = 1,
    MODULE_I2S_CHANNEL_MONO_LEFT = 2,
    MODULE_I2S_CHANNEL_MONO_RIGHT = 3,
} module_i2s_channel_mode_t;

typedef enum module_i2s_flags_t {
    MODULE_I2S_FLAG_USE_APLL = 1u << 0,
    MODULE_I2S_FLAG_AUTO_CLEAR_TX = 1u << 1,
} module_i2s_flags_t;

typedef int32_t module_socket_handle_t;

#define MODULE_SOCKET_INVALID (-1)

typedef enum module_socket_type_t {
    MODULE_SOCKET_TYPE_STREAM = 1,
    MODULE_SOCKET_TYPE_DGRAM = 2,
} module_socket_type_t;

typedef enum module_socket_poll_event_t {
    MODULE_SOCKET_POLL_READ = 1u << 0,
    MODULE_SOCKET_POLL_WRITE = 1u << 1,
    MODULE_SOCKET_POLL_ERROR = 1u << 2,
    MODULE_SOCKET_POLL_HANGUP = 1u << 3,
} module_socket_poll_event_t;

typedef enum module_socket_option_t {
    MODULE_SOCKET_OPT_REUSE_ADDR = 1,
    MODULE_SOCKET_OPT_BROADCAST = 2,
    MODULE_SOCKET_OPT_KEEP_ALIVE = 3,
    MODULE_SOCKET_OPT_TCP_NO_DELAY = 4,
    MODULE_SOCKET_OPT_RECV_TIMEOUT_MS = 5,
    MODULE_SOCKET_OPT_SEND_TIMEOUT_MS = 6,
} module_socket_option_t;

typedef enum module_socket_shutdown_t {
    MODULE_SOCKET_SHUTDOWN_READ = 1,
    MODULE_SOCKET_SHUTDOWN_WRITE = 2,
    MODULE_SOCKET_SHUTDOWN_BOTH = 3,
} module_socket_shutdown_t;

typedef enum module_netif_id_t {
    MODULE_NETIF_DEFAULT = 0,
    MODULE_NETIF_WIFI_STA = 1,
    MODULE_NETIF_WIFI_AP = 2,
} module_netif_id_t;

typedef enum module_netif_state_t {
    MODULE_NETIF_STATE_STARTED = 1u << 0,
    MODULE_NETIF_STATE_LINK_UP = 1u << 1,
    MODULE_NETIF_STATE_IPV4_READY = 1u << 2,
} module_netif_state_t;

/** IPv4 endpoint. Address bytes are in dotted-decimal order; port is host-endian. */
typedef struct module_socket_addr_t {
    uint32_t size;
    uint8_t address[4];
    uint16_t port;
    uint16_t reserved;
} module_socket_addr_t;

typedef struct module_socket_poll_item_t {
    uint32_t size;
    module_socket_handle_t socket;
    uint32_t events;
    uint32_t revents;
} module_socket_poll_item_t;

typedef struct module_netif_snapshot_t {
    uint32_t size;
    uint32_t generation;
    uint32_t state;
    uint8_t ipv4[4];
    uint8_t mac[6];
    uint8_t reserved[2];
} module_netif_snapshot_t;

typedef void *module_mdns_service_handle_t;

/** TXT strings are copied by register/update_txt before the call returns. */
typedef struct module_mdns_txt_record_t {
    const char *key;
    const char *value;
} module_mdns_txt_record_t;

typedef struct module_manifest_t {
    uint32_t magic;
    uint32_t abi_version;
    uint32_t size;
    const char *name;
    const char *version;
    const char *description;
    uint32_t flags;
    uint32_t min_host_version;
} module_manifest_t;

typedef struct module_open_info_t {
    uint32_t size;
    const char *name;
    const char *path;
    const char *app_dir;
    const char *data_dir;
    /* Non-zero only when this module may acquire owner-scoped BLE resources. */
    uint32_t owner_token;
} module_open_info_t;

typedef uint32_t module_ble_session_t;

/* Values intentionally match MicroPython bluetooth IRQ numbers. */
typedef enum module_ble_irq_t {
    MODULE_BLE_IRQ_SCAN_RESULT = 5,
    MODULE_BLE_IRQ_SCAN_DONE = 6,
    MODULE_BLE_IRQ_PERIPHERAL_CONNECT = 7,
    MODULE_BLE_IRQ_PERIPHERAL_DISCONNECT = 8,
    MODULE_BLE_IRQ_GATTC_SERVICE_RESULT = 9,
    MODULE_BLE_IRQ_GATTC_SERVICE_DONE = 10,
    MODULE_BLE_IRQ_GATTC_CHARACTERISTIC_RESULT = 11,
    MODULE_BLE_IRQ_GATTC_CHARACTERISTIC_DONE = 12,
    MODULE_BLE_IRQ_GATTC_DESCRIPTOR_RESULT = 13,
    MODULE_BLE_IRQ_GATTC_DESCRIPTOR_DONE = 14,
    MODULE_BLE_IRQ_GATTC_READ_RESULT = 15,
    MODULE_BLE_IRQ_GATTC_READ_DONE = 16,
    MODULE_BLE_IRQ_GATTC_WRITE_DONE = 17,
    MODULE_BLE_IRQ_GATTC_NOTIFY = 18,
    MODULE_BLE_IRQ_MTU_EXCHANGED = 21,
    MODULE_BLE_IRQ_ENCRYPTION_UPDATE = 28,
} module_ble_irq_t;

typedef enum module_ble_write_mode_t {
    MODULE_BLE_WRITE_NO_RESPONSE = 0,
    MODULE_BLE_WRITE_WITH_RESPONSE = 1,
} module_ble_write_mode_t;

/* Stable values matching NimBLE/Arduino address constants. */
typedef enum module_ble_addr_type_t {
    MODULE_BLE_ADDR_PUBLIC = 0,
    MODULE_BLE_ADDR_RANDOM = 1,
    MODULE_BLE_ADDR_PUBLIC_ID = 2,
    MODULE_BLE_ADDR_RANDOM_ID = 3,
} module_ble_addr_type_t;

typedef enum module_ble_own_addr_type_t {
    MODULE_BLE_OWN_ADDR_PUBLIC = 0,
    MODULE_BLE_OWN_ADDR_RANDOM = 1,
    MODULE_BLE_OWN_ADDR_RPA_PUBLIC_DEFAULT = 2,
    MODULE_BLE_OWN_ADDR_RPA_RANDOM_DEFAULT = 3,
} module_ble_own_addr_type_t;

typedef enum module_ble_io_capability_t {
    MODULE_BLE_IO_DISPLAY_ONLY = 0,
    MODULE_BLE_IO_DISPLAY_YESNO = 1,
    MODULE_BLE_IO_KEYBOARD_ONLY = 2,
    MODULE_BLE_IO_NO_INPUT_OUTPUT = 3,
    MODULE_BLE_IO_KEYBOARD_DISPLAY = 4,
} module_ble_io_capability_t;

typedef enum module_ble_characteristic_property_t {
    MODULE_BLE_CHAR_PROP_BROADCAST = 0x01,
    MODULE_BLE_CHAR_PROP_READ = 0x02,
    MODULE_BLE_CHAR_PROP_WRITE_NO_RESPONSE = 0x04,
    MODULE_BLE_CHAR_PROP_WRITE = 0x08,
    MODULE_BLE_CHAR_PROP_NOTIFY = 0x10,
    MODULE_BLE_CHAR_PROP_INDICATE = 0x20,
    MODULE_BLE_CHAR_PROP_AUTH_SIGNED_WRITE = 0x40,
    MODULE_BLE_CHAR_PROP_EXTENDED = 0x80,
} module_ble_characteristic_property_t;

/**
 * @brief BLE session configuration. Pass NULL for all defaults; mtu/rxbuf may be zero.
 */
typedef struct module_ble_config_t {
    uint32_t size;
    uint16_t mtu;
    uint16_t rxbuf;
    uint8_t bond;
    uint8_t mitm;
    uint8_t le_secure;
    uint8_t io_capability;
    uint8_t own_addr_type;
    uint8_t reserved[3];
    char gap_name[32];
} module_ble_config_t;

/**
 * @brief BLE scan parameters matching MicroPython: duration in ms, interval/window in us.
 */
typedef struct module_ble_scan_config_t {
    uint32_t size;
    uint32_t duration_ms;
    uint32_t interval_us;
    uint32_t window_us;
    uint8_t active;
    uint8_t reserved[3];
} module_ble_scan_config_t;

/**
 * @brief One copied BLE event. No pointer in this record outlives event_poll().
 */
typedef struct module_ble_event_t {
    uint32_t size;
    uint32_t irq;
    module_ble_session_t session;
    uint16_t conn_handle;
    uint16_t status;
    uint16_t start_handle;
    uint16_t end_handle;
    uint16_t def_handle;
    uint16_t value_handle;
    uint16_t descriptor_handle;
    uint16_t mtu;
    uint8_t properties;
    uint8_t addr_type;
    uint8_t adv_type;
    int16_t rssi;
    uint8_t encrypted;
    uint8_t authenticated;
    uint8_t bonded;
    uint8_t indication;
    uint8_t data_truncated;
    uint8_t reserved[2];
    char address[18];
    char uuid[40];
    uint16_t data_len;
    uint8_t data[244];
} module_ble_event_t;

typedef struct module_file_stat_t {
    uint32_t size;
    uint8_t is_directory;
    uint8_t reserved[3];
    uint64_t file_size;
    uint64_t modified_time;
} module_file_stat_t;

typedef struct module_display_desc_t {
    uint32_t size;
    uint16_t width;
    uint16_t height;
    uint32_t pixel_format;
    uint32_t flags;
} module_display_desc_t;

typedef struct module_display_caps_t {
    uint32_t size;
    uint16_t width;
    uint16_t height;
    uint32_t pixel_formats;
    uint16_t max_dma_rows;
    uint16_t reserved;
} module_display_caps_t;

typedef struct module_display_chunk_t {
    uint32_t size;
    void *pixels;
    uint16_t rows;
    uint16_t width;
    uint32_t pitch_bytes;
    uint32_t pixel_format;
} module_display_chunk_t;

typedef struct module_audio_desc_t {
    uint32_t size;
    uint32_t sample_rate;
    uint16_t bits_per_sample;
    uint16_t channels;
    uint32_t flags;
} module_audio_desc_t;

typedef struct module_i2s_config_t {
    uint32_t size;
    uint8_t port;
    uint8_t mode;
    uint16_t reserved0;
    uint32_t sample_rate;
    uint16_t bits;
    uint16_t channels;
    uint32_t format;
    uint32_t channel_mode;
    int16_t bclk_pin;
    int16_t ws_pin;
    int16_t dout_pin;
    int16_t din_pin;
    int16_t mclk_pin;
    int16_t reserved1;
    uint16_t dma_buf_count;
    uint16_t dma_buf_len;
    uint32_t flags;
} module_i2s_config_t;

typedef struct module_serial_api_t {
    uint32_t size;
    int32_t (*write)(const void *data, size_t len);
    int32_t (*print)(const char *text);
    int32_t (*println)(const char *text);
    void (*flush)(void);
} module_serial_api_t;

typedef struct module_sd_api_t {
    uint32_t size;
    int32_t (*begin)(void);
    int32_t (*mounted)(void);
    const char *(*mount_point)(void);
    int32_t (*exists)(const char *path);
    int32_t (*mkdir)(const char *path);
    int32_t (*remove)(const char *path);
    int32_t (*rename)(const char *from, const char *to);
    int32_t (*open)(const char *path, uint32_t mode, void **out_file);
} module_sd_api_t;

typedef struct module_file_api_t {
    uint32_t size;
    int32_t (*close)(void *file);
    int32_t (*available)(void *file, size_t *out_available);
    int32_t (*read)(void *file, void *buf, size_t len, size_t *out_read);
    int32_t (*write)(void *file, const void *buf, size_t len, size_t *out_written);
    int32_t (*seek)(void *file, int64_t offset, uint32_t mode);
    int32_t (*position)(void *file, uint64_t *out_pos);
    int32_t (*size_bytes)(void *file, uint64_t *out_size);
    int32_t (*flush)(void *file);
    int32_t (*is_directory)(void *file, int32_t *out_is_directory);
} module_file_api_t;

typedef struct module_display_api_t {
    uint32_t size;
    int32_t (*width)(void);
    int32_t (*height)(void);
    int32_t (*get_caps)(module_display_caps_t *out_caps);
    int32_t (*acquire)(const char *owner, const module_display_desc_t *desc, void **out_surface);
    int32_t (*release)(void *surface);
    int32_t (*startWrite)(void *surface);
    int32_t (*pushImageDMA)(void *surface, int16_t x, int16_t y,
                            uint16_t w, uint16_t h, const uint16_t *pixels);
    int32_t (*endWrite)(void *surface);
    int32_t (*fillScreen)(void *surface, uint16_t color);
    int32_t (*setAddrWindow)(void *surface, int32_t x, int32_t y, int32_t w, int32_t h);
    int32_t (*pushPixelsDMA)(void *surface, const uint16_t *pixels, size_t len);
    // Optional. Active same-task startWrite session and address window required.
    // OK = entire block queued (not completed); BUSY = no pixels accepted.
    // No waiting, splitting, allocation or blocking fallback. Buffer must remain
    // immutable/alive until successful dmaBusy reports 0 or endWrite completes.
    int32_t (*tryPushPixelsDMA)(void *surface, const uint16_t *pixels, size_t pixel_count);
    // Optional. Same-task active session only. On error out_busy stays 1.
    int32_t (*dmaBusy)(void *surface, int32_t *out_busy);
} module_display_api_t;

// Sensor-axis signed register counts, no software scaling/correction/fusion.
// Caller initializes size = sizeof(module_imu_raw_v1). Failure leaves out intact.
typedef struct module_imu_raw_v1 {
    uint32_t size;
    int16_t ax, ay, az, gx, gy, gz;
    uint32_t timestamp_ms; // Host acquisition time, wraps modulo 2^32.
    uint32_t seq;          // Successful acquisitions, wraps modulo 2^32.
} module_imu_raw_v1;

typedef struct module_imu_api_t {
    uint32_t size;
    // Optional. NOT_FOUND before first sample; otherwise last successful sample,
    // including during I2C failure/pause. No I2C access or heap allocation.
    int32_t (*readRaw)(module_imu_raw_v1 *out);
} module_imu_api_t;

typedef struct module_audio_api_t {
    uint32_t size;
    int32_t (*begin)(const module_audio_desc_t *desc, void **out_stream);
    int32_t (*write)(void *stream, const void *samples, size_t bytes, size_t *out_written);
    int32_t (*available)(void *stream, size_t *out_bytes);
    int32_t (*end)(void *stream);
} module_audio_api_t;

typedef struct module_i2s_api_t {
    uint32_t size;
    int32_t (*begin)(const module_i2s_config_t *cfg, void **out_stream);
    int32_t (*write)(void *stream, const void *data, size_t bytes,
                     size_t *out_written, uint32_t timeout_ms);
    int32_t (*read)(void *stream, void *data, size_t bytes,
                    size_t *out_read, uint32_t timeout_ms);
    int32_t (*availableForWrite)(void *stream, size_t *out_bytes);
    int32_t (*flush)(void *stream);
    int32_t (*mute)(void *stream);
    int32_t (*end)(void *stream);
} module_i2s_api_t;

typedef struct module_time_api_t {
    uint32_t size;
    uint32_t (*millis)(void);
    uint64_t (*micros)(void);
    void (*delay)(uint32_t ms);
    void (*yield)(void);
} module_time_api_t;

typedef struct module_heap_api_t {
    uint32_t size;
    void *(*malloc)(size_t size, uint32_t caps);
    void *(*calloc)(size_t n, size_t size, uint32_t caps);
    void *(*realloc)(void *ptr, size_t size, uint32_t caps);
    void (*free)(void *ptr);
    size_t (*free_size)(uint32_t caps);
    size_t (*largest_free_block)(uint32_t caps);
} module_heap_api_t;

typedef struct module_task_api_t {
    uint32_t size;
    int32_t (*create)(const char *name, void (*entry)(void *), void *arg,
                      uint32_t stack_bytes, uint32_t priority, int32_t core,
                      void **out_task);
    void (*remove)(void *task);
    void (*yield)(void);
    void (*delay)(uint32_t ms);
    int32_t (*create_ex)(const char *name, void (*entry)(void *), void *arg,
                         uint32_t stack_bytes, uint32_t priority, int32_t core,
                         uint32_t heap_caps, void **out_task);
} module_task_api_t;

typedef struct module_lua_api_t {
    uint32_t size;
    int (*gettop)(lua_State *L);
    void (*settop)(lua_State *L, int idx);
    int (*type)(lua_State *L, int idx);
    int (*istable)(lua_State *L, int idx);
    int (*isnil)(lua_State *L, int idx);
    int (*isnumber)(lua_State *L, int idx);
    int (*isstring)(lua_State *L, int idx);
    int (*toboolean)(lua_State *L, int idx);
    int64_t (*tointeger)(lua_State *L, int idx);
    double (*tonumber)(lua_State *L, int idx);
    const char *(*tostring)(lua_State *L, int idx);
    int64_t (*checkinteger)(lua_State *L, int idx);
    double (*checknumber)(lua_State *L, int idx);
    const char *(*checkstring)(lua_State *L, int idx);
    void *(*touserdata)(lua_State *L, int idx);
    void (*pushnil)(lua_State *L);
    void (*pushboolean)(lua_State *L, int value);
    void (*pushinteger)(lua_State *L, int64_t value);
    void (*pushnumber)(lua_State *L, double value);
    void (*pushstring)(lua_State *L, const char *text);
    void (*pushlightuserdata)(lua_State *L, void *ptr);
    void (*pushcfunction)(lua_State *L, module_lua_cfunction_t fn);
    void (*pushcclosure)(lua_State *L, module_lua_cfunction_t fn, int nup);
    void (*pushvalue)(lua_State *L, int idx);
    void (*newtable)(lua_State *L);
    void (*createtable)(lua_State *L, int narr, int nrec);
    void (*getfield)(lua_State *L, int idx, const char *key);
    void (*setfield)(lua_State *L, int idx, const char *key);
    void (*getglobal)(lua_State *L, const char *name);
    void (*setglobal)(lua_State *L, const char *name);
    int (*registry_ref)(lua_State *L);
    void (*registry_unref)(lua_State *L, int ref);
    void (*registry_rawgeti)(lua_State *L, int ref);
    int (*upvalue_index)(int n);
    int (*error)(lua_State *L, const char *msg);
    const char *(*tolstring)(lua_State *L, int idx, size_t *out_len);
    const char *(*checklstring)(lua_State *L, int idx, size_t *out_len);
    void (*pushlstring)(lua_State *L, const char *data, size_t len);
    void *(*newuserdata)(lua_State *L, size_t size);
} module_lua_api_t;

typedef struct module_runtime_api_t {
    uint32_t size;
    /**
     * Queue one no-argument Lua registry callback on L's owning Lua task and
     * wake that runtime. Repeated pending posts with the same (L, lua_ref) are
     * coalesced. The callback is invoked through lua_pcall().
     */
    int32_t (*event_post)(lua_State *L, int32_t lua_ref);
    /** Remove a pending callback before unref/teardown. */
    void (*event_cancel)(lua_State *L, int32_t lua_ref);
} module_runtime_api_t;

typedef struct module_diag_api_t {
    uint32_t size;
    int32_t (*update_context)(const dynmod_last_context_t *ctx);
    int32_t (*set_rom_path)(const char *rom_path);
    void (*heartbeat)(void);
} module_diag_api_t;

typedef struct module_dir_api_t {
    uint32_t size;
    int32_t (*open)(const char *path, void **out_dir);
    int32_t (*open_next)(void *dir, void **out_entry);
    const char *(*name)(void *entry);
    const char *(*path)(void *entry);
    int32_t (*is_dir)(void *entry, int32_t *out_is_dir);
    int32_t (*size_bytes)(void *entry, uint64_t *out_size);
    int32_t (*close)(void *handle);
} module_dir_api_t;

typedef struct module_ble_api_t {
    uint32_t size;
    int32_t (*open)(uint32_t owner_token, const module_ble_config_t *cfg,
                    module_ble_session_t *out_session);
    int32_t (*close)(module_ble_session_t session);
    int32_t (*gap_scan)(module_ble_session_t session, const module_ble_scan_config_t *cfg);
    int32_t (*gap_scan_stop)(module_ble_session_t session);
    int32_t (*gap_connect)(module_ble_session_t session, uint8_t addr_type,
                           const char *address, uint32_t timeout_ms);
    int32_t (*gap_disconnect)(module_ble_session_t session, uint16_t conn_handle);
    int32_t (*gap_pair)(module_ble_session_t session, uint16_t conn_handle, int32_t async_pair);
    int32_t (*gattc_discover_services)(module_ble_session_t session, uint16_t conn_handle,
                                       const char *uuid_or_null);
    int32_t (*gattc_discover_characteristics)(module_ble_session_t session, uint16_t conn_handle,
                                              uint16_t start_handle, uint16_t end_handle,
                                              const char *uuid_or_null);
    int32_t (*gattc_discover_descriptors)(module_ble_session_t session, uint16_t conn_handle,
                                          uint16_t start_handle, uint16_t end_handle);
    int32_t (*gattc_read)(module_ble_session_t session, uint16_t conn_handle, uint16_t value_handle);
    int32_t (*gattc_write)(module_ble_session_t session, uint16_t conn_handle, uint16_t value_handle,
                           const void *data, size_t data_len, uint32_t mode);
    int32_t (*gattc_exchange_mtu)(module_ble_session_t session, uint16_t conn_handle);
    int32_t (*event_poll)(module_ble_session_t session, module_ble_event_t *out_event);
    /* interval units: 1.25 ms; supervision_timeout units: 10 ms. */
    int32_t (*gap_set_connection_params)(module_ble_session_t session, uint16_t conn_handle,
                                         uint16_t min_interval, uint16_t max_interval,
                                         uint16_t latency, uint16_t supervision_timeout);
    int32_t (*gap_forget_device)(module_ble_session_t session, uint8_t addr_type,
                                 const char *address);
    int32_t (*gap_clear_bonds)(module_ble_session_t session);
    /* Emits ordered GATTC_READ_RESULT events (each no larger than event.data),
     * followed by one GATTC_READ_DONE. Offset is normally zero for a complete
     * value. */
    int32_t (*gattc_read_long)(module_ble_session_t session, uint16_t conn_handle,
                               uint16_t value_handle, uint16_t offset);
    int32_t (*gattc_write_long)(module_ble_session_t session, uint16_t conn_handle,
                                uint16_t value_handle, const void *data, size_t data_len);
    int32_t (*gap_get_rssi)(module_ble_session_t session, uint16_t conn_handle,
                            int16_t *out_rssi);
} module_ble_api_t;

typedef void *module_sync_handle_t;

typedef struct module_sync_api_t {
    uint32_t size;
    int32_t (*create_counting)(uint32_t max_count, uint32_t initial_count,
                               module_sync_handle_t *out_handle);
    int32_t (*create_mutex)(module_sync_handle_t *out_handle);
    int32_t (*take)(module_sync_handle_t handle, uint32_t timeout_ms);
    int32_t (*give)(module_sync_handle_t handle);
    void (*destroy)(module_sync_handle_t handle);
} module_sync_api_t;

/**
 * @brief Blocking IPv4 socket API intended for module-owned worker tasks.
 *
 * poll() returns MODULE_OK with out_ready == 0 on timeout. recv() on a stream
 * returns MODULE_OK with out_received == 0 for an orderly peer shutdown.
 * Buffer pointers are borrowed only for the duration of each call.
 */
typedef struct module_socket_api_t {
    uint32_t size;
    int32_t (*open)(uint32_t type, module_socket_handle_t *out_socket);
    int32_t (*bind)(module_socket_handle_t socket, const module_socket_addr_t *local_addr);
    int32_t (*listen)(module_socket_handle_t socket, uint32_t backlog);
    int32_t (*accept)(module_socket_handle_t listener,
                      module_socket_handle_t *out_socket,
                      module_socket_addr_t *out_peer_addr);
    int32_t (*connect)(module_socket_handle_t socket, const module_socket_addr_t *peer_addr);
    int32_t (*recv)(module_socket_handle_t socket, void *buf, size_t capacity,
                    size_t *out_received);
    int32_t (*recvfrom)(module_socket_handle_t socket, void *buf, size_t capacity,
                        size_t *out_received, module_socket_addr_t *out_peer_addr);
    int32_t (*send)(module_socket_handle_t socket, const void *data, size_t len,
                    size_t *out_sent);
    int32_t (*sendto)(module_socket_handle_t socket, const void *data, size_t len,
                      const module_socket_addr_t *peer_addr, size_t *out_sent);
    int32_t (*poll)(module_socket_poll_item_t *items, size_t count,
                    uint32_t timeout_ms, size_t *out_ready);
    int32_t (*setsockopt)(module_socket_handle_t socket, uint32_t option, int32_t value);
    int32_t (*getsockname)(module_socket_handle_t socket, module_socket_addr_t *out_local_addr);
    int32_t (*shutdown)(module_socket_handle_t socket, uint32_t how);
    int32_t (*close)(module_socket_handle_t socket);
} module_socket_api_t;

/**
 * @brief Race-free network-interface state queries and waits.
 *
 * wait_event() returns immediately when observed_generation is stale, otherwise
 * waits for the next start/link/IPv4 change. A timeout returns MODULE_ERR_BUSY.
 * out_snapshot is a current generation/state snapshot, so the host need not retain
 * an unbounded event history. Callers should query generation before reading
 * state/IP, then wait on that generation.
 */
typedef struct module_netif_api_t {
    uint32_t size;
    int32_t (*get_snapshot)(uint32_t netif, module_netif_snapshot_t *out_snapshot);
    int32_t (*wait_event)(uint32_t netif, uint32_t observed_generation,
                          uint32_t timeout_ms, module_netif_snapshot_t *out_snapshot);
} module_netif_api_t;

/** mDNS service handles are opaque; register/update_txt copy all input strings. */
typedef struct module_mdns_api_t {
    uint32_t size;
    int32_t (*service_register)(const char *instance,
                                const char *service_type,
                                const char *protocol,
                                uint16_t port,
                                const module_mdns_txt_record_t *txt_records,
                                size_t txt_count,
                                module_mdns_service_handle_t *out_handle);
    int32_t (*service_update_txt)(module_mdns_service_handle_t handle,
                                  const module_mdns_txt_record_t *txt_records,
                                  size_t txt_count);
    int32_t (*service_unregister)(module_mdns_service_handle_t handle);
} module_mdns_api_t;

typedef struct module_host_api_v2 {
    uint32_t abi_version;
    uint32_t size;
    module_serial_api_t serial;
    module_sd_api_t sd;
    module_file_api_t file;
    module_display_api_t display;
    module_audio_api_t audio;
    module_time_api_t time;
    module_heap_api_t heap;
    module_task_api_t task;
    module_lua_api_t lua;
    module_i2s_api_t i2s;
    module_diag_api_t diag;
    module_dir_api_t dir;
    module_ble_api_t ble;
    module_sync_api_t sync;
    module_socket_api_t socket;
    module_netif_api_t netif;
    module_mdns_api_t mdns;
    module_runtime_api_t runtime;
    module_imu_api_t imu;
} module_host_api_v2;

typedef const module_manifest_t *(*module_query_v1_fn)(void);
typedef int32_t (*module_host_resolve_v2_fn)(void *resolve_ctx, uint32_t proc_id, void **out_proc);
typedef int32_t (*module_create_v2_fn)(module_host_resolve_v2_fn resolve,
                                       void *resolve_ctx,
                                       const module_open_info_t *info,
                                       void **out_instance);
typedef int32_t (*module_luaopen_v1_fn)(void *instance, lua_State *L);
typedef void (*module_destroy_v1_fn)(void *instance);

#ifdef __cplusplus
}
#endif

/**
 * @brief Resolve one required host function by stable procedure ID.
 */
static inline int32_t module_sdk_resolve_required_v2(module_host_resolve_v2_fn resolve,
                                                     void *resolve_ctx,
                                                     uint32_t proc_id,
                                                     void **out_proc)
{
    int32_t err = MODULE_OK;
    if (!resolve || !out_proc)
    {
        return MODULE_ERR_INVALID_ARG;
    }

    *out_proc = NULL;
    err = resolve(resolve_ctx, proc_id, out_proc);
    if (err != MODULE_OK)
    {
        return err;
    }
    return *out_proc ? MODULE_OK : MODULE_ERR_UNSUPPORTED;
}

/**
 * @brief Resolve one optional host function by stable procedure ID.
 */
static inline int32_t module_sdk_resolve_optional_v2(module_host_resolve_v2_fn resolve,
                                                     void *resolve_ctx,
                                                     uint32_t proc_id,
                                                     void **out_proc)
{
    int32_t err = MODULE_OK;
    if (!resolve || !out_proc)
    {
        return MODULE_ERR_INVALID_ARG;
    }

    *out_proc = NULL;
    err = resolve(resolve_ctx, proc_id, out_proc);
    if (err == MODULE_ERR_NOT_FOUND || err == MODULE_ERR_UNSUPPORTED)
    {
        *out_proc = NULL;
        return MODULE_OK;
    }
    if (err != MODULE_OK)
    {
        return err;
    }
    return MODULE_OK;
}

/**
 * @brief Clear a module-local host table without depending on libc memset.
 */
static inline void module_sdk_zero_host_v2(module_host_api_v2 *out)
{
    unsigned char *p = NULL;
    size_t i = 0;
    if (!out)
    {
        return;
    }
    p = (unsigned char *)out;
    for (i = 0; i < sizeof(*out); ++i)
    {
        p[i] = 0;
    }
}

#ifdef __cplusplus
#define MODULE_SDK_CAST_PROC(slot, proc) reinterpret_cast<decltype(slot)>(proc)
#else
#define MODULE_SDK_CAST_PROC(slot, proc) ((__typeof__(slot))(proc))
#endif

#define MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, proc_id, slot) \
    do                                                                 \
    {                                                                  \
        void *_module_sdk_proc = NULL;                                 \
        int32_t _module_sdk_err = module_sdk_resolve_required_v2(      \
            (resolve), (resolve_ctx), (proc_id), &_module_sdk_proc);   \
        if (_module_sdk_err != MODULE_OK)                              \
        {                                                              \
            return _module_sdk_err;                                    \
        }                                                              \
        (slot) = MODULE_SDK_CAST_PROC(slot, _module_sdk_proc);         \
    } while (0)

#define MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, proc_id, slot) \
    do                                                                          \
    {                                                                           \
        void *_module_sdk_proc = NULL;                                          \
        int32_t _module_sdk_err = module_sdk_resolve_optional_v2(               \
            (resolve), (resolve_ctx), (proc_id), &_module_sdk_proc);            \
        if (_module_sdk_err != MODULE_OK)                                       \
        {                                                                       \
            return _module_sdk_err;                                             \
        }                                                                       \
        (slot) = MODULE_SDK_CAST_PROC(slot, _module_sdk_proc);                  \
    } while (0)

/**
 * @brief Build the module-local host table from stable host procedure IDs.
 *
 * The table is owned by the .so, so its field order is not part of the
 * firmware/module boundary. V2 modules cache only the stable MODULE_PROC_* IDs.
 */
static inline int32_t module_sdk_resolve_host_v2(module_host_resolve_v2_fn resolve,
                                                 void *resolve_ctx,
                                                 module_host_api_v2 *out)
{
    if (!out)
    {
        return MODULE_ERR_INVALID_ARG;
    }

    module_sdk_zero_host_v2(out);
    out->abi_version = MODULE_SDK_VERSION;
    out->size = sizeof(*out);

    out->serial.size = sizeof(out->serial);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SERIAL_WRITE_V1, out->serial.write);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SERIAL_PRINT_V1, out->serial.print);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SERIAL_PRINTLN_V1, out->serial.println);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SERIAL_FLUSH_V1, out->serial.flush);

    out->sd.size = sizeof(out->sd);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SD_BEGIN_V1, out->sd.begin);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SD_MOUNTED_V1, out->sd.mounted);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SD_MOUNT_POINT_V1, out->sd.mount_point);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SD_EXISTS_V1, out->sd.exists);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SD_MKDIR_V1, out->sd.mkdir);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SD_REMOVE_V1, out->sd.remove);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SD_RENAME_V1, out->sd.rename);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SD_OPEN_V1, out->sd.open);

    out->file.size = sizeof(out->file);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_FILE_CLOSE_V1, out->file.close);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_FILE_AVAILABLE_V1, out->file.available);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_FILE_READ_V1, out->file.read);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_FILE_WRITE_V1, out->file.write);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_FILE_SEEK_V1, out->file.seek);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_FILE_POSITION_V1, out->file.position);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_FILE_SIZE_BYTES_V1, out->file.size_bytes);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_FILE_FLUSH_V1, out->file.flush);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_FILE_IS_DIRECTORY_V1, out->file.is_directory);

    out->display.size = sizeof(out->display);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DISPLAY_WIDTH_V1, out->display.width);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DISPLAY_HEIGHT_V1, out->display.height);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DISPLAY_GET_CAPS_V1, out->display.get_caps);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DISPLAY_ACQUIRE_V1, out->display.acquire);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DISPLAY_RELEASE_V1, out->display.release);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DISPLAY_START_WRITE_V1, out->display.startWrite);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DISPLAY_PUSH_IMAGE_DMA_V1, out->display.pushImageDMA);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DISPLAY_END_WRITE_V1, out->display.endWrite);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DISPLAY_FILL_SCREEN_V1, out->display.fillScreen);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DISPLAY_SET_ADDR_WINDOW_V1, out->display.setAddrWindow);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DISPLAY_PUSH_PIXELS_DMA_V1, out->display.pushPixelsDMA);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DISPLAY_TRY_PUSH_PIXELS_DMA_V1, out->display.tryPushPixelsDMA);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DISPLAY_DMA_BUSY_V1, out->display.dmaBusy);

    out->audio.size = sizeof(out->audio);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_AUDIO_BEGIN_V1, out->audio.begin);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_AUDIO_WRITE_V1, out->audio.write);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_AUDIO_AVAILABLE_V1, out->audio.available);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_AUDIO_END_V1, out->audio.end);

    out->time.size = sizeof(out->time);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_TIME_MILLIS_V1, out->time.millis);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_TIME_MICROS_V1, out->time.micros);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_TIME_DELAY_V1, out->time.delay);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_TIME_YIELD_V1, out->time.yield);

    out->heap.size = sizeof(out->heap);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_HEAP_MALLOC_V1, out->heap.malloc);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_HEAP_CALLOC_V1, out->heap.calloc);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_HEAP_REALLOC_V1, out->heap.realloc);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_HEAP_FREE_V1, out->heap.free);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_HEAP_FREE_SIZE_V1, out->heap.free_size);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_HEAP_LARGEST_FREE_BLOCK_V1, out->heap.largest_free_block);

    out->task.size = sizeof(out->task);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_TASK_CREATE_V1, out->task.create);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_TASK_REMOVE_V1, out->task.remove);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_TASK_YIELD_V1, out->task.yield);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_TASK_DELAY_V1, out->task.delay);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_TASK_CREATE_EX_V1, out->task.create_ex);

    out->lua.size = sizeof(out->lua);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_GETTOP_V1, out->lua.gettop);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_SETTOP_V1, out->lua.settop);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_TYPE_V1, out->lua.type);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_ISTABLE_V1, out->lua.istable);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_ISNIL_V1, out->lua.isnil);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_ISNUMBER_V1, out->lua.isnumber);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_ISSTRING_V1, out->lua.isstring);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_TOBOOLEAN_V1, out->lua.toboolean);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_TOINTEGER_V1, out->lua.tointeger);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_TONUMBER_V1, out->lua.tonumber);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_TOSTRING_V1, out->lua.tostring);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_CHECKINTEGER_V1, out->lua.checkinteger);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_CHECKNUMBER_V1, out->lua.checknumber);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_CHECKSTRING_V1, out->lua.checkstring);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_TOUSERDATA_V1, out->lua.touserdata);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_PUSHNIL_V1, out->lua.pushnil);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_PUSHBOOLEAN_V1, out->lua.pushboolean);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_PUSHINTEGER_V1, out->lua.pushinteger);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_PUSHNUMBER_V1, out->lua.pushnumber);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_PUSHSTRING_V1, out->lua.pushstring);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_PUSHLIGHTUSERDATA_V1, out->lua.pushlightuserdata);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_PUSHCFUNCTION_V1, out->lua.pushcfunction);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_PUSHCCLOSURE_V1, out->lua.pushcclosure);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_PUSHVALUE_V1, out->lua.pushvalue);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_NEWTABLE_V1, out->lua.newtable);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_CREATETABLE_V1, out->lua.createtable);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_GETFIELD_V1, out->lua.getfield);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_SETFIELD_V1, out->lua.setfield);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_GETGLOBAL_V1, out->lua.getglobal);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_SETGLOBAL_V1, out->lua.setglobal);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_REGISTRY_REF_V1, out->lua.registry_ref);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_REGISTRY_UNREF_V1, out->lua.registry_unref);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_REGISTRY_RAWGETI_V1, out->lua.registry_rawgeti);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_UPVALUE_INDEX_V1, out->lua.upvalue_index);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_ERROR_V1, out->lua.error);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_TOLSTRING_V1, out->lua.tolstring);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_CHECKLSTRING_V1, out->lua.checklstring);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_PUSHLSTRING_V1, out->lua.pushlstring);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_NEWUSERDATA_V1, out->lua.newuserdata);

    out->i2s.size = sizeof(out->i2s);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_I2S_BEGIN_V1, out->i2s.begin);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_I2S_WRITE_V1, out->i2s.write);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_I2S_READ_V1, out->i2s.read);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_I2S_AVAILABLE_FOR_WRITE_V1, out->i2s.availableForWrite);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_I2S_FLUSH_V1, out->i2s.flush);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_I2S_MUTE_V1, out->i2s.mute);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_I2S_END_V1, out->i2s.end);

    out->diag.size = sizeof(out->diag);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DIAG_UPDATE_CONTEXT_V1, out->diag.update_context);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DIAG_SET_ROM_PATH_V1, out->diag.set_rom_path);
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DIAG_HEARTBEAT_V1, out->diag.heartbeat);

    out->dir.size = sizeof(out->dir);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DIR_OPEN_V2, out->dir.open);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DIR_OPEN_NEXT_V2, out->dir.open_next);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DIR_NAME_V2, out->dir.name);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DIR_PATH_V2, out->dir.path);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DIR_IS_DIR_V2, out->dir.is_dir);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DIR_SIZE_BYTES_V2, out->dir.size_bytes);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_DIR_CLOSE_V2, out->dir.close);

    out->ble.size = sizeof(out->ble);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_OPEN_V1, out->ble.open);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_CLOSE_V1, out->ble.close);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_GAP_SCAN_V1, out->ble.gap_scan);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_GAP_SCAN_STOP_V1, out->ble.gap_scan_stop);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_GAP_CONNECT_V1, out->ble.gap_connect);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_GAP_DISCONNECT_V1, out->ble.gap_disconnect);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_GAP_PAIR_V1, out->ble.gap_pair);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_GATTC_DISCOVER_SERVICES_V1, out->ble.gattc_discover_services);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_GATTC_DISCOVER_CHARACTERISTICS_V1, out->ble.gattc_discover_characteristics);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_GATTC_DISCOVER_DESCRIPTORS_V1, out->ble.gattc_discover_descriptors);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_GATTC_READ_V1, out->ble.gattc_read);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_GATTC_WRITE_V1, out->ble.gattc_write);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_GATTC_EXCHANGE_MTU_V1, out->ble.gattc_exchange_mtu);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_EVENT_POLL_V1, out->ble.event_poll);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_GAP_SET_CONNECTION_PARAMS_V1, out->ble.gap_set_connection_params);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_GAP_FORGET_DEVICE_V1, out->ble.gap_forget_device);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_GAP_CLEAR_BONDS_V1, out->ble.gap_clear_bonds);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_GATTC_READ_LONG_V1, out->ble.gattc_read_long);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_GATTC_WRITE_LONG_V1, out->ble.gattc_write_long);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_BLE_GAP_GET_RSSI_V1, out->ble.gap_get_rssi);

    out->sync.size = sizeof(out->sync);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SYNC_CREATE_COUNTING_V1, out->sync.create_counting);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SYNC_CREATE_MUTEX_V1, out->sync.create_mutex);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SYNC_TAKE_V1, out->sync.take);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SYNC_GIVE_V1, out->sync.give);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SYNC_DESTROY_V1, out->sync.destroy);

    out->socket.size = sizeof(out->socket);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SOCKET_OPEN_V1, out->socket.open);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SOCKET_BIND_V1, out->socket.bind);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SOCKET_LISTEN_V1, out->socket.listen);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SOCKET_ACCEPT_V1, out->socket.accept);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SOCKET_CONNECT_V1, out->socket.connect);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SOCKET_RECV_V1, out->socket.recv);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SOCKET_RECVFROM_V1, out->socket.recvfrom);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SOCKET_SEND_V1, out->socket.send);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SOCKET_SENDTO_V1, out->socket.sendto);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SOCKET_POLL_V1, out->socket.poll);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SOCKET_SETSOCKOPT_V1, out->socket.setsockopt);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SOCKET_GETSOCKNAME_V1, out->socket.getsockname);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SOCKET_SHUTDOWN_V1, out->socket.shutdown);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_SOCKET_CLOSE_V1, out->socket.close);

    out->netif.size = sizeof(out->netif);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_NETIF_GET_SNAPSHOT_V1, out->netif.get_snapshot);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_NETIF_WAIT_EVENT_V1, out->netif.wait_event);

    out->mdns.size = sizeof(out->mdns);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_MDNS_SERVICE_REGISTER_V1, out->mdns.service_register);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_MDNS_SERVICE_UPDATE_TXT_V1, out->mdns.service_update_txt);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_MDNS_SERVICE_UNREGISTER_V1, out->mdns.service_unregister);

    out->runtime.size = sizeof(out->runtime);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_RUNTIME_EVENT_POST_V1, out->runtime.event_post);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_RUNTIME_EVENT_CANCEL_V1, out->runtime.event_cancel);

    out->imu.size = sizeof(out->imu);
    MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2(resolve, resolve_ctx, MODULE_PROC_IMU_READ_RAW_V1, out->imu.readRaw);

    return MODULE_OK;
}

#undef MODULE_SDK_RESOLVE_OPTIONAL_PROC_V2
#undef MODULE_SDK_RESOLVE_PROC_V2
#undef MODULE_SDK_CAST_PROC
