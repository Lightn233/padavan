THISDIR = $(shell pwd)
all:

clean:

romfs:
	$(ROMFSINST) -p +x $(THISDIR)/aliddns.sh /usr/bin/aliddns.sh
	$(ROMFSINST) -p +x $(THISDIR)/aliddns-legacy.sh /usr/bin/aliddns-legacy.sh
	$(ROMFSINST) -p +x $(THISDIR)/aliddns-ip.sh /usr/bin/aliddns-ip.sh
	$(ROMFSINST) /etc_ro/ddns_script.sh