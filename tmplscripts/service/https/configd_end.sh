#!/bin/bash
# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only

/opt/vyatta/sbin/vyatta-update-webgui-listen-addr.pl
if [ -x /opt/vyatta/sbin/vyatta-webgui2-service-cli ]; then
    /opt/vyatta/sbin/vyatta-webgui2-service-cli
fi

if [[ ${COMMIT_ACTION} = 'DELETE' ]]; then
    service lighttpd stop
    service vyatta-webgui-chunker-aux stop
else
    service lighttpd restart
    service vyatta-webgui-chunker-aux restart
fi
