#include <fcntl.h>
#include <signal.h>
#include <time.h>
#include <sys/klog.h>
#include <stdarg.h>
#include <sys/wait.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <unistd.h>
#include <limits.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <httpd.h>

#include <shutils.h>

#define FW_CREATE	0
#define FW_APPEND	1
#define FW_NEWLINE	2

// for backup =========================================================

int f_write(const char *path, const void *buffer, int len, unsigned flags, unsigned cmode)
{
	static const char nl = '\n';
	int f;
	int r = -1;
	mode_t m;

	m = umask(0);
	if (cmode == 0) cmode = 0666;
	if ((f = open(path, (flags & FW_APPEND) ? (O_WRONLY|O_CREAT|O_APPEND) : (O_WRONLY|O_CREAT|O_TRUNC), cmode)) >= 0) {
		if ((buffer == NULL) || ((r = write(f, buffer, len)) == len)) {
			if (flags & FW_NEWLINE) {
				if (write(f, &nl, 1) == 1) ++r;
			}
		}
		close(f);
	}
	umask(m);
	return r;
}

// for bandwidth =========================================================

int f_exists(const char *path)	// note: anything but a directory
{
	struct stat st;
	return (stat(path, &st) == 0) && (!S_ISDIR(st.st_mode));
}

static int _f_wait_exists(const char *name, int max, int invert)
{
	max *= 40;
	while (max-- > 0) {
		if (f_exists(name) ^ invert)
			return 1;
		usleep(25000);
	}
	return 0;
}

int f_wait_exists(const char *name, int max)
{
	return _f_wait_exists(name, max, 0);
}

int f_read(const char *path, void *buffer, int max)
{
	int f;
	int n;

	if ((f = open(path, O_RDONLY)) < 0) return -1;
	n = read(f, buffer, max);
	close(f);
	return n;
}

int f_read_string(const char *path, char *buffer, int max)
{
	if (max <= 0) return -1;
	int n = f_read(path, buffer, max - 1);
	buffer[(n > 0) ? n : 0] = 0;
	return n;
}

size_t strlcpy(char *d, const char *s, size_t bufsize)
{
	size_t len = strlen(s);
	size_t ret = len;
	if (bufsize <= 0) return 0;
	if (len >= bufsize) len = bufsize-1;
	memcpy(d, s, len);
	d[len] = 0;
	return ret;
}

/**
 * hex char to int
 * @author 荒野无灯
 * @date 2016-08-01 12:30
 * @param hex
 * @return int
 */
static int hex_char_to_int(const uint8_t *hex)
{
	int val;
	if(*hex >= '0' && *hex <='9') {
		val = (*hex - '0') * 16;
	} else {
		val = (*hex - 'A' + 10) * 16;
	}

	if(*(hex+1) >= '0' && *(hex+1) <='9') {
		val += (*(hex+1) - '0');
	} else {
		val += (*(hex+1) - 'A' +10);
	}

	return val;
}


/**
 * @author 荒野无灯
 * @date 2016-08-01 12:30
 * @param str the str to detect
 * @param sz string total bytes
 * @return
 */
static int can_be_chinese_utf8(const uint8_t *str, int sz)
{
	int len = strlen (str);
	if (sz < 6) {
		return 0;
	}

	if ((len >= 6) &&
		(hex_char_to_int(str) >= 0xe4 && hex_char_to_int(str) <= 0xe9)
		&& (hex_char_to_int(str+2) >= 0x80 && hex_char_to_int(str+2) <= 0xbf)
		&& (hex_char_to_int(str+4) >= 0x80 && hex_char_to_int(str+4) <= 0xbf)
	) {
		return 1;
	}

	if (((sz - len >= 2) && (len >=4)) &&
		(hex_char_to_int(str-2) >= 0xe4 && hex_char_to_int(str-2) <= 0xe9)
		&& (hex_char_to_int(str) >= 0x80 && hex_char_to_int(str) <= 0xbf)
		&& (hex_char_to_int(str+2) >= 0x80 && hex_char_to_int(str+2) <= 0xbf)
	) {
		return 1;
	}

	if (((sz - len >= 4) && (len >= 2)) &&
		(hex_char_to_int(str-4) >= 0xe4 && hex_char_to_int(str-4) <= 0xe9)
		&& ((hex_char_to_int(str-2) >= 0x80 && hex_char_to_int(str-2) <= 0xbf)
		&& (hex_char_to_int(str) >= 0x80 && hex_char_to_int(str) <= 0xbf))
	) {
		return 1;
	}

	return 0;
}


/**
 * @author 荒野无灯
 * @date 2016-08-01 12:30
 * @param str the str to detect
 * @param sz string total bytes
 * @return int
 */
static int can_be_ascii_utf8(const uint8_t *str, int sz)
{
	int ch;
	if (sz < 2 || strlen((const char *)str) < 2)
		return 0;
	ch = hex_char_to_int(str);
	return (ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'Z') ||
	       (ch >= 'a' && ch <= 'z') || (ch != 0 && strchr("!*()_-' .", ch) && ch != ' ');
}

/**
 * @param input the string to validate
 * @author 荒野无灯
 * @date 2016-08-01 12:30
 * @return int
 */
static int is_valid_hex_string(const uint8_t *input)
{
	int i;
	int input_len, input_hex_len;
	const uint8_t *input_ptr;

	//detect from index 2, skip char "0x"
	input_ptr = input+2;
	input_len = strlen(input);
	input_hex_len = input_len -2;

	int is_valid_ascii_or_Chinese = 1;

	//0xAA
	if(input_len >4 && input_len % 2 == 0 && input[0] == '0' && input[1] == 'x') {
		for ( i=2; i < input_len; i += 2, input_ptr += 2) {
			if (!( ((*input_ptr>='0' && *input_ptr <='9') || ( *input_ptr >='A' && *input_ptr <='F')) && ((*(input_ptr+1) >='0' && *(input_ptr+1) <='9') || ( *(input_ptr+1) >='A' && *(input_ptr+1) <='F')))) {
				is_valid_ascii_or_Chinese = 0;
				break;
			}
			if (!can_be_chinese_utf8(input_ptr, input_hex_len) && !can_be_ascii_utf8(input_ptr, input_hex_len)) {
				is_valid_ascii_or_Chinese = 0;
				break;
			}
		}
	} else {
		is_valid_ascii_or_Chinese = 0;
	}
	return is_valid_ascii_or_Chinese;
}

int
char_to_ascii(char *output, size_t capacity, const char *input)
{
	static const char hex[] = "0123456789ABCDEF";
	size_t i, used = 0;
	const unsigned char *bytes = (const unsigned char *)input;
	if (!capacity)
		return -1;
	output[0] = 0;
	if (is_valid_hex_string(bytes)) {
		for (i = 2; bytes[i]; i += 2) {
			if (3 >= capacity - used) { output[0] = 0; return -1; }
			output[used++] = '%'; output[used++] = bytes[i]; output[used++] = bytes[i+1];
		}
		output[used] = 0;
		return 0;
	}
	for (i = 0; bytes[i]; i++) {
		unsigned char ch = bytes[i];
		int plain = (ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'Z') ||
		            (ch >= 'a' && ch <= 'z') || strchr("!*()_-' .", ch) != NULL;
		/* 空格仍按原表单规则编码；所有字节都按无符号值转换。 */
		if (ch == ' ') plain = 0;
		if ((plain ? 1U : 3U) >= capacity - used) {
			output[0] = 0;
			return -1;
		}
		if (plain) output[used++] = ch;
		else {
			output[used++] = '%';
			output[used++] = hex[ch >> 4];
			output[used++] = hex[ch & 15];
		}
	}
	output[used] = 0;
	return 0;
}

int do_f(const char *path, webs_t wp)
{
	FILE *fp;
	char buf[1024];
	int ret = 0;

	fp = fopen(path, "r");
	if (fp) {
		while (fgets(buf, sizeof(buf), fp))
			ret += fputs(buf, wp);
		fclose(fp);
	} else {
		ret += fputs("", wp);
	}

	fflush(wp);

	return ret;
}

