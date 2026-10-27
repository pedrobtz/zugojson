/* zugojson_r.c -- the R entry points.

   Every call into Goose goes through goose_r_run(). A Goose runtime
   failure then comes back here as a message, after the data stacks have
   been rewound, and only then is the R condition raised. A body may call
   R, but holds R objects only in something protected before the call. */

#include <limits.h>
#include <stdint.h>

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

#include "goose_r_runtime.h"
#include "zugojson_goose.h"

#define ERRLEN 512

/* A result for the R side: c(kind, text). kind is "" on success, "parse"
   for a JSON syntax error and "runtime" for a Goose runtime failure; R
   turns the last two into classed conditions. */
static SEXP result(const char *kind, const char *text, int64_t n) {
  if (n > INT_MAX) {
    kind = "runtime";
    text = "result is longer than an R string can hold";
    n = -1;
  }
  SEXP out = PROTECT(Rf_allocVector(STRSXP, 2));
  SET_STRING_ELT(out, 0, Rf_mkChar(kind));
  SET_STRING_ELT(out, 1, n < 0 ? Rf_mkCharCE(text, CE_UTF8)
                               : Rf_mkCharLenCE(text, (int) n, CE_UTF8));
  UNPROTECT(1);
  return out;
}

static sl_u8 slice_of(SEXP x) {
  SEXP s = STRING_ELT(x, 0);
  sl_u8 in = {(uint8_t *) CHAR(s), (int64_t) LENGTH(s)};
  return in;
}

/* --- format ------------------------------------------------------------- */

typedef struct {
  sl_u8 in;
  int64_t indent, n;
  const uint8_t *out;
} format_call;

static void format_body(void *p) {
  format_call *c = p;
  c->out = zugojson_format(c->in, c->indent, &c->n);
}

SEXP zugojson_c_format(SEXP x, SEXP pretty) {
  format_call c = {slice_of(x), Rf_asLogical(pretty) ? 0 : -1, 0, NULL};
  char err[ERRLEN];
  if (goose_r_run(format_body, &c, err, sizeof err))
    return result("runtime", err, -1);
  /* Rendered JSON never starts with '!'; a syntax error always does. */
  if (c.n > 0 && c.out[0] == '!')
    return result("parse", (const char *) c.out + 1, c.n - 1);
  return result("", (const char *) c.out, c.n);
}

/* --- validate ----------------------------------------------------------- */

typedef struct {
  sl_u8 in;
  int64_t n;
} check_call;

static void check_body(void *p) {
  check_call *c = p;
  (void) zugojson_check(c->in, &c->n);
}

SEXP zugojson_c_valid(SEXP x) {
  R_xlen_t len = XLENGTH(x);
  SEXP out = PROTECT(Rf_allocVector(LGLSXP, len));
  int *o = LOGICAL(out);
  char err[ERRLEN];
  for (R_xlen_t i = 0; i < len; i++) {
    SEXP s = STRING_ELT(x, i);
    if (s == NA_STRING) {
      o[i] = NA_LOGICAL;
      continue;
    }
    check_call c = {{(uint8_t *) CHAR(s), (int64_t) LENGTH(s)}, 0};
    if (goose_r_run(check_body, &c, err, sizeof err)) {
      UNPROTECT(1);
      return result("runtime", err, -1);
    }
    o[i] = c.n == 0;
  }
  UNPROTECT(1);
  return out;
}

/* --- test hook ---------------------------------------------------------- */

typedef struct {
  int64_t i, v;
} probe_call;

static void probe_body(void *p) {
  probe_call *c = p;
  c->v = zugojson_index_probe(c->i);
}

SEXP zugojson_c_index_probe(SEXP i) {
  probe_call c = {(int64_t) Rf_asInteger(i), 0};
  char err[ERRLEN];
  if (goose_r_run(probe_body, &c, err, sizeof err))
    return result("runtime", err, -1);
  return Rf_ScalarReal((double) c.v);
}

/* Test hook: a body that grows the stacks, calls fn() in R and then, if
   asked, fails in Goose. holder is protected outside goose_r_run(), so the
   body never needs PROTECT. */

typedef struct {
  SEXP holder;
  int fail_after;
  int64_t v;
} callback_call;

static const uint8_t *callback_input(int64_t *n) {
  static uint8_t buf[2 * 10000 + 1];
  static int64_t len = 0;
  if (!len) {
    for (int k = 0; k < 10000; k++) {
      buf[len++] = k ? ',' : '[';
      buf[len++] = '1';
    }
    buf[len++] = ']';
  }
  *n = len;
  return buf;
}

static void callback_body(void *p) {
  callback_call *c = p;
  sl_u8 in;
  int64_t n;
  in.data = (uint8_t *) callback_input(&in.len);
  (void) zugojson_format(in, 0, &n);
  SEXP call = VECTOR_ELT(c->holder, 0);
  SET_VECTOR_ELT(c->holder, 1, Rf_eval(call, R_GlobalEnv));
  if (c->fail_after) c->v = zugojson_index_probe(7);
}

SEXP zugojson_c_callback_probe(SEXP fn, SEXP fail_after) {
  SEXP holder = PROTECT(Rf_allocVector(VECSXP, 2));
  SET_VECTOR_ELT(holder, 0, Rf_lang1(fn));
  callback_call c = {holder, Rf_asLogical(fail_after) == TRUE, 0};
  char err[ERRLEN];
  if (goose_r_run(callback_body, &c, err, sizeof err)) {
    UNPROTECT(1);
    return result("runtime", err, -1);
  }
  UNPROTECT(1);
  return R_NilValue;
}

SEXP zugojson_c_stack_use(void) {
  double use[64];
  int n = goose_r_stack_use(use, 64);
  SEXP out = PROTECT(Rf_allocVector(REALSXP, n));
  for (int i = 0; i < n; i++) REAL(out)[i] = use[i];
  UNPROTECT(1);
  return out;
}

SEXP zugojson_c_fault_handler_installed(void) {
  return Rf_ScalarLogical(goose_r_fault_handler_installed());
}

/* --- registration ------------------------------------------------------- */

static void init_body(void *unused) {
  static char name[] = "zugojson";
  static char *argv[] = {name, NULL};
  (void) unused;
  goose_init(1, argv);
}

static const R_CallMethodDef call_methods[] = {
    {"zugojson_c_format", (DL_FUNC) &zugojson_c_format, 2},
    {"zugojson_c_valid", (DL_FUNC) &zugojson_c_valid, 1},
    {"zugojson_c_index_probe", (DL_FUNC) &zugojson_c_index_probe, 1},
    {"zugojson_c_callback_probe", (DL_FUNC) &zugojson_c_callback_probe, 2},
    {"zugojson_c_stack_use", (DL_FUNC) &zugojson_c_stack_use, 0},
    {"zugojson_c_fault_handler_installed",
     (DL_FUNC) &zugojson_c_fault_handler_installed, 0},
    {NULL, NULL, 0}};

void R_init_zugojson(DllInfo *dll) {
  char err[ERRLEN];
  if (goose_r_run(init_body, NULL, err, sizeof err))
    Rf_error("zugojson: cannot start the Goose runtime: %s", err);
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
