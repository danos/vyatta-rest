#!/bin/bash
# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only

if [ ! -f /etc/lighttpd/server.pem ]; then
    openssl req -new -x509 -keyout /etc/lighttpd/server.pem \
	-out /etc/lighttpd/server.pem \
	-days 3650 -nodes -passout pass:'' \
	-subj '/C=US/CN=Vyatta Web GUI/O=AT&T Inc/ST=TX/L=Dallas'
fi
