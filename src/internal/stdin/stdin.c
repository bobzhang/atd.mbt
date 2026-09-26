#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"

// Read all of standard input, which may be a pipe.
MOONBIT_FFI_EXPORT moonbit_bytes_t atd_read_all_stdin(void) {
  size_t cap = 4096, len = 0, n;
  char *buf = malloc(cap);
  if (buf == NULL) return moonbit_make_bytes(0, 0);
  while ((n = fread(buf + len, 1, cap - len, stdin)) > 0) {
    len += n;
    if (len == cap) {
      char *nbuf = realloc(buf, cap * 2);
      if (nbuf == NULL) break;
      buf = nbuf;
      cap *= 2;
    }
  }
  moonbit_bytes_t res = moonbit_make_bytes((int32_t)len, 0);
  memcpy(res, buf, len);
  free(buf);
  return res;
}
