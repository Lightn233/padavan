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

#include <stdio.h>
#include <stdlib.h>
#define __USE_GNU
#include <string.h>
#include <ctype.h>
#include <stdint.h>
#include <limits.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/reboot.h>

#include <image.h>

#include "common.h"
#include "httpd.h"

#ifndef O_BINARY
#define O_BINARY	0
#endif

#define IMAGE_HEADER		"HDR0"
#define PROFILE_HEADER		"HDR1"
#define PROFILE_HEADER_NEW	"HDR2"
#define UPLOAD_BUF_SIZE		1024
#define UPLOAD_TAIL_SIZE	128

typedef int (*check_header_t)(const char *, long *);

static int
check_header_bz2(const char *buf, long *file_len)
{
	const unsigned char bz2h_1[3] = { 0x42, 0x5a, 0x68 };
	const unsigned char bz2h_2[6] = { 0x31, 0x41, 0x59, 0x26, 0x53, 0x59 };

	if (memcmp(buf, bz2h_1, 3) == 0 && memcmp(buf+4, bz2h_2, 6) == 0)
		return 0;

	httpd_log("%s: Incorrect %s header!", "Storage restore", "BZ2");

	return -1;
}

static int
check_header_nvram(const char *buf, long *file_len)
{
	uint32_t raw_len;
	memcpy(&raw_len, buf + 4, sizeof(raw_len));

	if (strncmp(buf, PROFILE_HEADER_NEW, 4) == 0) {
		*file_len = (long)(raw_len & 0xffffffU);
		return 0;
	}

	if (strncmp(buf, PROFILE_HEADER, 4) == 0) {
		if (raw_len > LONG_MAX) return -1;
		*file_len = (long)raw_len;
		return 0;
	}

	httpd_log("%s: Incorrect %s header!", "NVRAM restore", "profile");

	return -1;
}

static int
check_header_image(const char *buf, long *file_len)
{
	int pid_asus_len;
	uint32_t payload_size;
	unsigned int partition_size;
	char pid_asus[16];
	image_header_t *hdr = (image_header_t *)buf;

	/* check header magic */
	if (ntohl(hdr->ih_magic) != IH_MAGIC) {
		httpd_log("%s: Incorrect %s header!", "Firmware update", "image");
		return -1;
	}

	pid_asus_len = strlen(BOARD_PID);
	if (pid_asus_len > 12)
		pid_asus_len = 12;

	strncpy(pid_asus, buf+36, pid_asus_len);
	pid_asus[pid_asus_len] = 0;

	if (strcmp(pid_asus, BOARD_PID) != 0) {
		httpd_log("%s: Incorrect image ProductID: %s! Expected is %s.", "Firmware update", pid_asus, BOARD_PID);
		return -2;
	}

	/* 先检查减法形式的上限，再相加；32 位 long 不能接收溢出的镜像长度。 */
    payload_size = ntohl(hdr->ih_size);
    partition_size = get_mtd_size(FW_MTD_NAME);
    if (partition_size < sizeof(image_header_t) ||
        payload_size > partition_size - sizeof(image_header_t) ||
        payload_size > (unsigned long)LONG_MAX - sizeof(image_header_t))
        return -1;
    *file_len = (long)payload_size + (long)sizeof(image_header_t);

	return 0;
}

static int
check_crc_image(const char *fw_image)
{
	int ifd;
	uint32_t checksum, datalen;
	struct stat sbuf;
	unsigned char *ptr = (unsigned char *)MAP_FAILED;
	image_header_t header2;
	image_header_t *hdr, *hdr2=&header2;
	int ret = 0;

	ifd = open(fw_image, O_RDONLY|O_BINARY);
	if (ifd < 0)
		return -1;

	/* We're a bit of paranoid */
#if defined(_POSIX_SYNCHRONIZED_IO) && !defined(__sun__) && !defined(__FreeBSD__)
	(void) fdatasync (ifd);
#else
	(void) fsync (ifd);
#endif
	if (fstat(ifd, &sbuf) < 0) {
		ret=-1;
		goto checkcrc_fail;
	}

	if (sbuf.st_size < (off_t)(sizeof(image_header_t) + (2 * 1024 * 1024)) ||
	    (uint64_t)sbuf.st_size > get_mtd_size(FW_MTD_NAME)) {
		ret = -1;
		httpd_log("%s: Firmware image size is invalid!", "Firmware update");
		goto checkcrc_fail;
	}

	ptr = (unsigned char *)mmap(0, sbuf.st_size, PROT_READ, MAP_SHARED, ifd, 0);
	if (ptr == (unsigned char *)MAP_FAILED) {
		ret = -1;
		httpd_log("%s: Unable to mmap firmware image!", "Firmware update");
		goto checkcrc_fail;
	}

	hdr = (image_header_t *)ptr;

	memcpy(hdr2, hdr, sizeof(image_header_t));
	memset(&hdr2->ih_hcrc, 0, sizeof(uint32_t));
	checksum = crc32_sp(0, (const char *)hdr2, sizeof(image_header_t));

	if (checksum != ntohl(hdr->ih_hcrc)) {
		ret = -1;
		httpd_log("%s: Firmware image %s has invalid CRC!", "Firmware update", "header");
		goto checkcrc_fail;
	}

	datalen = ntohl(hdr->ih_size);
	if (datalen > ((unsigned int)sbuf.st_size - sizeof(image_header_t))) {
		ret = -1;
		httpd_log("%s: Firmware image is corrupted! Please check free space in /tmp!", "Firmware update");
		goto checkcrc_fail;
	}

	checksum = crc32_sp(0, (const char *)(ptr + sizeof(image_header_t)), datalen);
	if (checksum != ntohl(hdr->ih_dcrc)) {
		ret = -1;
		httpd_log("%s: Firmware image %s has invalid CRC!", "Firmware update", "body");
		goto checkcrc_fail;
	}

checkcrc_fail:
	if (ptr != (unsigned char *)MAP_FAILED)
		munmap((void *)ptr, sbuf.st_size);

#if defined(_POSIX_SYNCHRONIZED_IO) && !defined(__sun__) && !defined(__FreeBSD__)
	(void) fdatasync (ifd);
#else
	(void) fsync (ifd);
#endif
	close(ifd);

	return ret;
}

/* 逐字节核减请求剩余量；头部过长、嵌入零字节或提前结束都拒绝。 */
static int
read_upload_line(FILE *stream, int *remaining, char *line, size_t capacity)
{
    size_t used = 0;
    while (*remaining > 0 && used + 1 < capacity) {
        int c = fgetc(stream);
        if (c == EOF || c == 0) return -1;
        (*remaining)--;
        line[used++] = (char)c;
        if (c == '\n') { line[used] = 0; return (int)used; }
    }
    return -1;
}

static int
do_upload_file(FILE *stream, int clen, char *bndr, const char *fn, const char *obj_name, check_header_t func_hdr, int hdr_size)
{
    FILE *fp = NULL;
    char buf[UPLOAD_TAIL_SIZE + UPLOAD_BUF_SIZE + 1], buf_obj[32], *ptr;
    int count, offset = 0, ret = -1, valid_header = 0, found_part = 0;
    int found_blank = 0, found_boundary = 0;
    long filelen;
    size_t tail_length = 0;

    snprintf(buf_obj, sizeof(buf_obj), "name=\"%s\"", obj_name);
    if (clen <= 0 || hdr_size <= 0 || hdr_size > UPLOAD_BUF_SIZE) goto out;
    while (clen > 0) {
        if (read_upload_line(stream, &clen, buf, sizeof(buf)) < 0) goto out;
        if (!strncasecmp(buf, "Content-Disposition:", 20) && strstr(buf, buf_obj)) {
            found_part = 1; break;
        }
    }
    if (!found_part) goto out;
    while (clen > 0) {
        if (read_upload_line(stream, &clen, buf, sizeof(buf)) < 0) goto out;
        if (!strcmp(buf, "\n") || !strcmp(buf, "\r\n")) { found_blank = 1; break; }
    }
    if (!found_blank || clen < hdr_size) goto out;
    unlink(fn);
    fp = fopen(fn, "w+");
    if (!fp) goto out;
    filelen = clen;
    ptr = buf + UPLOAD_TAIL_SIZE;

    while (clen > 0 && filelen > 0) {
        count = (int)fread(ptr + offset, 1, MIN(clen, UPLOAD_BUF_SIZE - offset), stream);
        if (count <= 0) goto out;
        clen -= count;
        if (!valid_header) {
            if (count + offset < hdr_size) { offset += count; continue; }
            count += offset; offset = 0;
            if (func_hdr(ptr, &filelen) != 0 || filelen < hdr_size ||
                filelen > (long)count + clen) goto out;
            valid_header = 1;
        }
        if (bndr) {
            char *pb = memmem(ptr - tail_length, tail_length + count, bndr, strlen(bndr));
            if (!pb) pb = memmem(ptr - tail_length, tail_length + count, bndr + 1, strlen(bndr + 1));
            if (pb) {
                found_boundary = 1;
                if (pb < ptr) {
                    /* 边界跨越两次读取：截去此前暂存到文件尾部的边界字节。 */
                    off_t end;
                    if (fflush(fp) || (end = ftello(fp)) < (off_t)(ptr - pb) ||
                        ftruncate(fileno(fp), end - (ptr - pb))) goto out;
                    filelen = 0; break;
                }
                count = (int)(pb - ptr); filelen = count;
            }
        }
        if ((long)count > filelen) count = (int)filelen;
        if (count < 0 || count > UPLOAD_BUF_SIZE) goto out;
        if (fwrite(ptr, 1, (size_t)count, fp) != (size_t)count) goto out;
        filelen -= count;
        if (bndr) {
            tail_length = MIN((size_t)count, (size_t)UPLOAD_TAIL_SIZE);
            memcpy(ptr - tail_length, ptr + count - tail_length, tail_length);
        }
    }
    if (!valid_header || filelen != 0 || (bndr && !found_boundary) || ferror(stream)) goto out;
    ret = 0;
out:
    /* 成功后读完已声明的 multipart 尾部，避免未读请求触发连接复位。 */
    while (ret == 0 && clen > 0) {
        count = (int)fread(buf, 1, MIN(clen, (int)sizeof(buf)), stream);
        if (count <= 0) { ret = -1; break; }
        clen -= count;
    }
    if (fp && fclose(fp)) ret = -1;
    if (ret) unlink(fn);
    return ret;
}

void
do_upgrade_fw_post(const char *url, FILE *stream, int clen, char *boundary)
{
	const char *upload_file = FW_IMG_NAME;
	int ret;

	/* delete some files (need free space in /tmp) */
	unlink("/tmp/usb.log");
	unlink("/tmp/syscmd.log");
	doSystem("rm -rf %s", "/tmp/xupnpd-cache");
	doSystem("rm -rf %s", "/tmp/xupnpd-feeds");

	/* copy mtd_write to RAM */
	doSystem("cp -f %s %s", "/bin/mtd_write", "/tmp");

	/* reclaim RAM from caches */
	fput_int("/proc/sys/vm/drop_caches", 1);

	ret = do_upload_file(stream, clen, NULL, upload_file, "file", check_header_image, sizeof(image_header_t));
	if (ret == 0) {
		ret = check_crc_image(upload_file);
		if (ret != 0)
			unlink(upload_file);
	}
	if (ret != 0) http_input_error = 400;
}

void
do_restore_nv_post(const char *url, FILE *stream, int clen, char *boundary)
{
	const char *upload_file = PROFILE_FIFO_UPLOAD;

	if (do_upload_file(stream, clen, NULL, upload_file, "file_nv", check_header_nvram, 8))
		http_input_error = 400;
}

void
do_restore_st_post(const char *url, FILE *stream, int clen, char *boundary)
{
	const char *upload_file = STORAGE_FIFO_FILENAME;
	char bndr[128];

	/* BZ2 not store file length in the header, check boundary marker */
	if (!boundary || !*boundary || strlen(boundary) > 70 ||
        strpbrk(boundary, "\r\n")) {
        unlink(upload_file); http_input_error = 400; return;
    }
    snprintf(bndr, sizeof(bndr), "\r\n--%s", boundary);
    if (do_upload_file(stream, clen, bndr, upload_file, "file_st", check_header_bz2, 10))
        http_input_error = 400;
}
