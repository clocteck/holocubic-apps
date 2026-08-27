idf_component_register(
    SRCS
        "jpg_module.c"
    INCLUDE_DIRS
        "."
    REQUIRES
        espressif__esp_jpeg
        espressif__esp_new_jpeg
)

target_compile_options(${COMPONENT_LIB} PRIVATE
    -O2
    -fPIC
    -fvisibility=hidden
    -fdata-sections
    -ffunction-sections
    -fno-jump-tables
    -fno-tree-switch-conversion
    -fno-builtin-memcpy
    -fno-builtin-memmove
    -fno-builtin-memset
    -fno-builtin-strlen
    -fno-builtin-strcpy
    -fno-builtin-malloc
    -fno-builtin-free
)

idf_build_get_property(jpg_build_dir BUILD_DIR)
idf_component_get_property(jpg_jpeg_dir espressif__esp_jpeg COMPONENT_DIR)
idf_component_get_property(jpg_jpeg_lib espressif__esp_jpeg COMPONENT_LIB)
idf_component_get_property(jpg_new_jpeg_dir espressif__esp_new_jpeg COMPONENT_DIR)

target_compile_options(${jpg_jpeg_lib} PRIVATE
    -O2
    -fPIC
    -fvisibility=hidden
    -fdata-sections
    -ffunction-sections
    -fno-jump-tables
    -fno-tree-switch-conversion
)

set(jpg_so_include_dirs
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${jpg_build_dir}/config"
    "${IDF_PATH}/components/newlib/platform_include"
    "${IDF_PATH}/components/esp_common/include"
    "${IDF_PATH}/components/esp_system/include"
    "${IDF_PATH}/components/esp_rom/include"
    "${IDF_PATH}/components/esp_rom/${IDF_TARGET}/include"
    "${IDF_PATH}/components/log/include"
    "${IDF_PATH}/components/soc/include"
    "${IDF_PATH}/components/soc/${IDF_TARGET}/include"
    "${IDF_PATH}/components/soc/${IDF_TARGET}/register"
    "${IDF_PATH}/components/hal/include"
    "${IDF_PATH}/components/heap/include"
    "${jpg_jpeg_dir}/include"
    "${jpg_new_jpeg_dir}/include"
)

foreach(jpg_so_include_dir IN LISTS jpg_so_include_dirs)
    idf_build_set_property(COMPILE_INCLUDE_DIRECTORIES "${jpg_so_include_dir}" APPEND)
endforeach()
