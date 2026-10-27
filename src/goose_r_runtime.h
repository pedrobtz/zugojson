/* goose_r_runtime.h -- running Goose-generated C inside an R process. */
#ifndef GOOSE_R_RUNTIME_H
#define GOOSE_R_RUNTIME_H

#include <stddef.h>

/* Runs body(data) with Goose's guard-page handler installed. Returns 0 on
   success. On a Goose runtime failure (bounds check, abort, data stack
   overflow) it restores every data stack to where it was before the call,
   copies the message into err and returns 1. A call made while another is
   running is refused the same way.

   body may call R. An R error or interrupt in it restores the stacks and
   R's handlers, then R carries on unwinding. body holds R objects only in
   something protected before the call, never with PROTECT: a Goose failure
   jumps over any UNPROTECT. */
int goose_r_run(void (*body)(void *), void *data, char *err, size_t errlen);

/* Test hooks. Writes top - base for up to max data stacks into use and
   returns how many it wrote. */
int goose_r_stack_use(double *use, int max);

/* 1 while Goose's SIGSEGV handler is the installed one. */
int goose_r_fault_handler_installed(void);

#endif
