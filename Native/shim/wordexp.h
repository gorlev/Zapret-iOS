// Stand-in for <wordexp.h>, which iOS marks unavailable. See Native/ios_compat.c.
#pragma once
#include <stddef.h>
typedef struct { size_t we_wordc; char **we_wordv; size_t we_offs; } wordexp_t;
#define WRDE_NOCMD 0x04
#define WRDE_NOSPACE 4
int wordexp(const char *words, wordexp_t *we, int flags);
void wordfree(wordexp_t *we);
