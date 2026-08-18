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
} module_open_info_t;

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
} module_display_api_t;

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

typedef struct module_diag_api_t {
    uint32_t size;
    int32_t (*update_context)(const dynmod_last_context_t *ctx);
    int32_t (*set_rom_path)(const char *rom_path);
    void (*heartbeat)(void);
} module_diag_api_t;

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
    MODULE_SDK_RESOLVE_PROC_V2(resolve, resolve_ctx, MODULE_PROC_LUA_NEWUSERDATA_V1, out->lua.newuserdata);

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

    return MODULE_OK;
}

#undef MODULE_SDK_RESOLVE_PROC_V2
#undef MODULE_SDK_CAST_PROC
