/*
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston,
 * MA 02111-1307 USA 
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>

/* Use SVID search */
#include <search.h>

/* CGI hash table */
static struct hsearch_data *htab = NULL;

static int
hex_value(unsigned char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/* 原地单次扫描；拒绝残缺转义和嵌入零字节，避免重叠复制及静默截断。 */
int
unescape(char *s)
{
    unsigned char *read = (unsigned char *)s, *write = read;
    while (*read) {
        unsigned char c = *read++;
        if (c == '%') {
            int hi, lo;
            if (!read[0] || !read[1]) return 400;
            hi = hex_value(read[0]); lo = hex_value(read[1]);
            if (hi < 0 || lo < 0 || (hi == 0 && lo == 0)) return 400;
            c = (unsigned char)((hi << 4) | lo);
            read += 2;
        } else if (c == '+') c = ' ';
        *write++ = c;
    }
    *write = 0;
    return 0;
}

char *
get_cgi(char *name)
{
	ENTRY e, *ep;

	if (htab == NULL) return NULL;

	e.key = name;
	hsearch_r(e, FIND, &ep, htab);

	return ep ? ep->data : NULL;
}

int
set_cgi(char *name, char *value)
{
	ENTRY e, *ep;

	if (htab == NULL) return 500;

	e.key = name;
	hsearch_r(e, FIND, &ep, htab);
	if (ep)
		ep->data = value;
	else {
		e.data = value;
		if (!hsearch_r(e, ENTER, &ep, htab)) return 500;
	}
	return 0;
}

int
init_cgi(char *query)
{
    size_t nel = 1;
    char *cursor, *pair, *name, *value;
    int error;

    if (htab != NULL) {
        hdestroy_r(htab);
        free(htab);
        htab = NULL;
    }
    if (!query || !*query) return 0;

    for (cursor = query; *cursor; cursor++)
        if (*cursor == '&' || *cursor == ';') nel++;
    htab = calloc(1, sizeof(*htab));
    if (!htab) return 500;
    if (!hcreate_r(nel, htab)) { free(htab); htab = NULL; return 500; }

    cursor = query;
    while ((pair = strsep(&cursor, "&;")) != NULL) {
        value = pair;
        name = strsep(&value, "=");
        /* 先拆原始分隔符，再分别解码；%26、%3D 不会变成额外参数。 */
        error = unescape(name);
        if (!error && value) error = unescape(value);
        if (!error && value) error = set_cgi(name, value);
        if (error) { init_cgi(NULL); return error; }
    }
    return 0;
}
