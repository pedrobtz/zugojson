/* zugojson_r.c -- the R entry points.

   Every call into Goose goes through goose_r_run(). A Goose runtime
   failure then comes back here as a message, after the data stacks have
   been rewound, and only then is anything done with R's API. Nothing in a
   body function may call R: an R error raised inside goose_r_run() would
   jump over the stack rewind and leave Goose's fault handler installed. */

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
    {NULL, NULL, 0}};

void R_init_zugojson(DllInfo *dll) {
  char err[ERRLEN];
  if (goose_r_run(init_body, NULL, err, sizeof err))
    Rf_error("zugojson: cannot start the Goose runtime: %s", err);
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
