#pragma once
#include <stddef.h>
/* Caller frees the form-encoded request. MD5 is protocol-only, not auth. */
char *ncm_eapi(const char *path, const char *json, size_t length);
char *ncm_weapi(const char *json, size_t length);
