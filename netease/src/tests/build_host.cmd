@echo off
setlocal
call "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1
cd /d "%~dp0"
if not exist build mkdir build
cd build
cl /nologo /LD /O2 /DNDEBUG /DMBEDTLS_CONFIG_FILE=\"ncm_crypto_config.h\" /I"..\..\main" /I"..\..\vendor\mbedtls\include" /I"..\..\vendor\qrcode" "..\..\main\ncm_crypto.c" "..\..\main\ncm_dsp.c" "..\..\vendor\mbedtls\library\aes.c" "..\..\vendor\mbedtls\library\md5.c" "..\..\vendor\mbedtls\library\platform_util.c" "..\..\vendor\qrcode\qrcodegen.c" "..\\test_output.c" /link /OUT:ncm_test.dll /EXPORT:ncm_eapi /EXPORT:ncm_weapi /EXPORT:ncm_dsp_configure /EXPORT:ncm_dsp_sample /EXPORT:qrcodegen_encodeText /EXPORT:qrcodegen_getSize /EXPORT:qrcodegen_getModule /EXPORT:ncm_test_output_gain /EXPORT:ncm_test_output_sample /EXPORT:ncm_test_ring_write /EXPORT:ncm_test_ring_read /EXPORT:ncm_test_png_header /EXPORT:ncm_test_png_init
exit /b %errorlevel%
