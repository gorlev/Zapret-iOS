// iOS has no wordexp(); tpws uses it only for "@file" config files, which the
// app never passes. These stand-ins refuse that option and free nothing.
#include <wordexp.h>
int wordexp(const char *words, wordexp_t *we, int flags) { (void)words; (void)flags; we->we_wordc = 0; we->we_wordv = 0; return WRDE_NOSPACE; }
void wordfree(wordexp_t *we) { (void)we; }
