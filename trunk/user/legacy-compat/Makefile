THISDIR = $(shell pwd)
CFLAGS += -Os -Wall -Wextra -Werror
all: legacy-config
legacy-config: legacy-config.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)
clean:
	rm -f legacy-config
romfs: legacy-config
	$(ROMFSINST) -p +x $(THISDIR)/legacy-config /usr/bin/legacy-config
	$(ROMFSINST) -p 644 $(THISDIR)/legacy-service.sh /etc_ro/legacy-service.sh
