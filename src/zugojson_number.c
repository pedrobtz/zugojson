/* zugojson_number.c -- number conversion for the Goose parser.

   The parser checks a number against JSON's grammar and hands the text
   here, through the extern fn zugojson_strtod in zugojson.goose. strtod is
   correctly rounded, which Goose's own parse_flt is not for long mantissas
   and large exponents.

   This runs inside goose_r_run(), so it must not call R's API. */

#include <locale.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "zugojson_goose.h"

/* goose_r_runtime.c: reports a failure back to goose_r_run(). */
void gs_panic(const char *msg) __attribute__((noreturn));

double zugojson_strtod(sl_u8 s) {
  char small[128];
  char *buf = small;
  size_t n = (size_t) s.len;
  if (n >= sizeof small) {
    buf = malloc(n + 1);
    if (!buf) gs_panic("out of memory reading a number");
  }
  memcpy(buf, s.data, n);
  buf[n] = '\0';

  /* strtod reads the locale's decimal point. R keeps LC_NUMERIC at "C",
     but a package's C code can change it, so translate rather than
     assume. JSON text has only '.' and ASCII digits here. */
  const char *dp = localeconv()->decimal_point;
  if (dp && dp[0] && dp[0] != '.' && !dp[1]) {
    char *p = memchr(buf, '.', n);
    if (p) *p = dp[0];
  }

  double v = strtod(buf, NULL);
  if (buf != small) free(buf);
  return v;
}
