pppd_plugin_LTLIBRARIES = pptp.la
pppd_plugindir = $(PPPD_PLUGIN_DIR)
pptp_la_CPPFLAGS = -I${top_srcdir} -I${top_builddir}/pppd -DPLUGINVERSION=\"0.8.5\"
pptp_la_LDFLAGS = -module -avoid-version
pptp_la_SOURCES = pptp.c pptp_callmgr.c pptp_ctrl.c pptp_quirks.c orckit_quirks.c util.c vector.c dirutil.c
