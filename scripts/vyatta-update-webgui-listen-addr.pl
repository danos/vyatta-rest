#!/usr/bin/perl
#
# Module: vyatta-update-webgui-listen-addr.pl
# Description: updates the ssl listen configuration
#
# Copyright (c) 2017-2020, AT&T Intellectual Property. All rights reserved.
# Copyright (c) 2014 by Brocade Communications Systems, Inc.
# All rights reserved.
# Copyright (c) 2009-2013 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use warnings;
use lib "/opt/vyatta/share/perl5/";
use File::Slurp qw( :edit );

use Vyatta::Config;

my $config = new Vyatta::Config;

my @addrs      = $config->returnValues("service https listen-address");
my $http_redir = $config->returnValue("service https http-redirect");
my $conf_file  = "/etc/lighttpd/lighttpd.conf";

#
# For IPv6, depending on whether listening on a specific address has been
# configured, comment out the config for port bindings using the unspecified
# address so that the application is no longer listening for incoming
# connections on all available interfaces.
#
sub enable_ipv6_listen_all_intf {
    edit_file_lines { $_ = "$1\n" if /^# (.*::.*)/ } $conf_file;
}

sub disable_ipv6_listen_all_intf {
    edit_file_lines { $_ = "# $_" if /^[^#].*::/ } $conf_file;
}

open my $fp, ">", "/etc/lighttpd/conf-enabled/10-ssl.conf";

print $fp "## lighttpd support for SSLv2 and SSLv3\n";
print $fp "## \n";
print $fp "## Documentation: /usr/share/doc/lighttpd-doc/ssl.txt\n";
print $fp "##http://www.lighttpd.net/documentation/ssl.html \n";
print $fp "\n";
print $fp "#### SSL engine\n";
print $fp "\n";
print $fp "ssl.engine                = \"enable\"\n";
print $fp "ssl.pemfile               = \"/etc/lighttpd/server.pem\"\n";
print $fp "ssl.use-sslv2             = \"disable\"\n";
print $fp "ssl.use-sslv3             = \"disable\"\n";
print $fp "ssl.cipher-list           = \"TLSv1.2+HIGH !PSK !ARIA !CAMELLIA\"\n";

if ( $#addrs >= 0 ) {
    print $fp "server.bind               = \"127.0.0.1\"\n";
    foreach my $addr (@addrs) {
        if ( $addr =~ /:/ ) {
            print $fp "\$SERVER[\"socket\"] == \"[$addr]:443\" {\n";
        }
        else {
            print $fp "\$SERVER[\"socket\"] == \"$addr:443\" {\n";
        }
        print $fp
          "                  ssl.engine                  = \"enable\"\n";
        print $fp
"                  ssl.pemfile                 = \"/etc/lighttpd/server.pem\"\n";
        print $fp
          "                  ssl.use-sslv2               = \"disable\"\n";
        print $fp
          "                  ssl.use-sslv3               = \"disable\"\n";
        print $fp
"                  ssl.cipher-list             = \"TLSv1.2+HIGH !PSK !ARIA !CAMELLIA\"\n";
        print $fp "}\n";
        if ( defined($http_redir) && $http_redir eq "enable" ) {

            if ( $addr =~ /:/ ) {
                print $fp "\$SERVER[\"socket\"] == \"[$addr]:80\" {\n";
            }
            else {
                print $fp "\$SERVER[\"socket\"] == \"$addr:80\" {\n";
            }
            print $fp
              "                  ssl.engine                  = \"disable\"\n";
            print $fp "}\n";
        }
    }
    disable_ipv6_listen_all_intf();
}
else {
    if ( defined($http_redir) && $http_redir eq "enable" ) {
        print $fp "\$SERVER[\"socket\"] == \"0.0.0.0:80\" {\n";
        print $fp
          "                  ssl.engine                  = \"disable\"\n";
        print $fp "}\n";
    }
    enable_ipv6_listen_all_intf();
}

close $fp;

exit 0;
