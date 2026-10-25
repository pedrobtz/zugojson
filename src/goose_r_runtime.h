/* goose_r_runtime.h -- running Goose-generated C inside an R process. */
#ifndef GOOSE_R_RUNTIME_H
#define GOOSE_R_RUNTIME_H

#include <stddef.h>

/* Runs body(data) with Goose's guard-page handler installed. Returns 0 on
   success. On a Goose runtime failure (bounds check, abort, data stack
   overflow) it restores every data stack to where it was before the call,
   copies the message into err and returns 1. body must not call R's API:
   an R error raised inside it would skip the restore. */
int goose_r_run(void (*body)(void *), void *data, char *err, size_t errlen);

#endif
