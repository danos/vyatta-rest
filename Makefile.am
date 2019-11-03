# SPDX-License-Identifier: GPL-2.0-only
share_perl5dir = /opt/vyatta/share/perl5/Vyatta
share_perl5_webgui2dir = $(share_perl5dir)/WebGUI2
configdir = /opt/vyatta/etc/config
demodir = /opt/vyatta/demo	
tmpdir = $(prefix)/tmp/webgui2
chunkerpiddir = $(prefix)/var/run
wwwdir = /var/www
initddir = /etc/init.d
cgidir = /usr/lib/cgi-bin
cfgrootdir = $(datadir)/vyatta-cfg
opdir = $(datadir)/vyatta-op/templates
perldir = $(datadir)/perl5
perl_appdir = $(perldir)/App
perl_app_paramdir = $(perl_appdir)/Param
tmplscriptdir = $(datadir)/tmplscripts

ssbindir = /usr/sbin

AM_CPPFLAGS = -D NO_FCGI_DEFINES -I /usr/include/vyatta-cfg/ -I src/server -Wall -DDEBUG -g -std=c++0x

CLEANFILES = src/server/main.o src/server/interface.o src/server/command.o src/server/authenticate.o src/server/process.o src/server/http.o src/server/common.o src/server/multirespcmd.o src/server/mode.o src/server/appmode.o src/server/servicemode.o src/server/opmode.o src/serverconfmode.o src/server/chunker2_main.o src/server/chunker2_manager.o src/server/chunker2_processor.o src/server/rl_str_proc.o src/server/configuration.o src/server/authbasic.o src/server/authsession.o

src_server_chunker2_SOURCES = src/server/chunker2_main.cc
src_server_chunker2_SOURCES += src/server/chunker2_manager.cc
src_server_chunker2_SOURCES += src/server/chunker2_processor.cc
src_server_chunker2_SOURCES += src/server/common.cc
src_server_chunker2_SOURCES += src/server/http.cc

src_server_rest_SOURCES = src/server/main.cc
src_server_rest_SOURCES += src/server/command.cc
src_server_rest_SOURCES += src/server/process.cc
src_server_rest_SOURCES += src/server/interface.cc
src_server_rest_SOURCES += src/server/authenticate.cc
src_server_rest_SOURCES += src/server/authbasic.cc
src_server_rest_SOURCES += src/server/authsession.cc
src_server_rest_SOURCES += src/server/http.cc
src_server_rest_SOURCES += src/server/multirespcmd.cc
src_server_rest_SOURCES += src/server/mode.cc
src_server_rest_SOURCES += src/server/appmode.cc
src_server_rest_SOURCES += src/server/servicemode.cc
src_server_rest_SOURCES += src/server/opmode.cc
src_server_rest_SOURCES += src/server/confmode.cc
src_server_rest_SOURCES += src/server/permissions.cc
src_server_rest_SOURCES += src/server/common.cc
src_server_rest_SOURCES += src/server/configuration.cc
src_server_rest_SOURCES += src/server/rl_str_proc.cc

src_server_chunker2_LDADD = -lcurl
src_server_chunker2_LDADD += -laudit
src_server_chunker2_LDADD += -ljansson

src_server_rest_LDADD = -lopdclient
src_server_rest_LDADD += -lpam
src_server_rest_LDADD += -lcurl
src_server_rest_LDADD += -lfcgi
src_server_rest_LDADD += -lssl
src_server_rest_LDADD += -lcrypto
src_server_rest_LDADD += -ljansson
src_server_rest_LDADD += -lvyatta-config
src_server_rest_LDADD += -lvyatta-util
src_server_rest_LDADD += -laudit

bin_PROGRAMS = src/server/rest

ssbin_PROGRAMS = src/server/chunker2

initd_SCRIPTS = scripts/vyatta-webgui-chunker-aux

# app-mode perl library
perl_app_DATA = src/server/lib/perl5/App/Msg.pm
perl_app_DATA += src/server/lib/perl5/App/MsgParser.pm
perl_app_DATA += src/server/lib/perl5/App/MsgSimple.pm
perl_app_DATA += src/server/lib/perl5/App/MapSimple.pm
perl_app_param_DATA = src/server/lib/perl5/App/Param/Base.pm
perl_app_param_DATA += src/server/lib/perl5/App/Param/Util.pm
perl_app_param_DATA += src/server/lib/perl5/App/Param/NonParam.pm
perl_app_param_DATA += src/server/lib/perl5/App/Param/TypelessParam.pm
perl_app_param_DATA += src/server/lib/perl5/App/Param/TxtParam.pm
perl_app_param_DATA += src/server/lib/perl5/App/Param/U32Param.pm
perl_app_param_DATA += src/server/lib/perl5/App/Param/Ipv4Param.pm
perl_app_param_DATA += src/server/lib/perl5/App/Param/Ipv4netParam.pm
perl_app_param_DATA += src/server/lib/perl5/App/Param/Ipv6Param.pm
perl_app_param_DATA += src/server/lib/perl5/App/Param/Ipv6netParam.pm
perl_app_param_DATA += src/server/lib/perl5/App/Param/MacaddrParam.pm
perl_app_param_DATA += src/server/lib/perl5/App/Param/BoolParam.pm
perl_app_param_DATA += src/server/lib/perl5/App/Param/TagParam.pm
perl_app_param_DATA += src/server/lib/perl5/App/Param/MultiTypeParam.pm

share_perl5_webgui2_DATA = lib/Vyatta/WebGUI2/SessionKey.pm

# app handlers
sbin_SCRIPTS = scripts/vyatta-webgui2-op.pl
sbin_SCRIPTS += scripts/vyatta-webgui2-shell.pl
sbin_SCRIPTS += scripts/vyatta-update-webgui-listen-addr.pl
sbin_SCRIPTS += scripts/vyatta-webgui2-service-cli

# library
AM_CFLAGS = -I src/lib -Wall 
AM_YFLAGS = -d --name-prefix=yy_`basename $* .y`_
AM_LFLAGS = --prefix=yy_`basename $* .l`_ -olex.yy.c
cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
				cpio -0pd

# XXX get Ext here for now
install-exec-hook:
	mkdir -p $(DESTDIR)$(chunkerpiddir)/
	mkdir -p $(DESTDIR)$(tmpdir)/
	touch $(DESTDIR)$(tmpdir)/dummy

	mkdir -p $(DESTDIR)/$(cgidir)/
	cp scripts/vyatta-app $(DESTDIR)/$(cgidir)/
	cp scripts/vyatta-service $(DESTDIR)/$(cgidir)/
	install -m 755 scripts/disabled.cgi $(DESTDIR)/$(cgidir)/

	mkdir -p $(DESTDIR)$(wwwdir)/rest
	touch $(DESTDIR)$(wwwdir)/rest/app
	touch $(DESTDIR)$(wwwdir)/rest/service
	touch $(DESTDIR)$(wwwdir)/rest/op
	touch $(DESTDIR)$(wwwdir)/rest/conf
	touch $(DESTDIR)$(wwwdir)/rest/perm

	@mkdir -p $(DESTDIR)$(opdir); \
	cd templates-op; $(cpiop) $(DESTDIR)$(opdir)

	mkdir -p $(DESTDIR)$(tmplscritdir)
	cd tmplscripts && $(cpiop) $(DESTDIR)$(tmplscriptdir)
