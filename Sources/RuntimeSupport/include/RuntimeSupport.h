#ifndef AKITO_RUNTIME_SUPPORT_H
#define AKITO_RUNTIME_SUPPORT_H
#include <stddef.h>
size_t akito_zlib_bound(size_t count);
int akito_zlib_compress(const unsigned char *input, size_t count, unsigned char *output, size_t *output_count);
int akito_zip_extract(const unsigned char *input, size_t count, int method, int fd, unsigned long long expected, unsigned long crc);
#endif
