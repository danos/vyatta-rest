#!/usr/bin/perl
#
# Module: vyatta-webgui2-shell.pl
# Description: vyatta-webgui2-shell sample
#
# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2014 by Brocade Communications Systems, Inc.
# All rights reserved.
# Copyright (c) 2009-2013 Vyatta, Inc.
#
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use warnings;
use lib "/opt/vyatta/share/perl5/";
use Term::ReadKey;
use POSIX;
use MIME::Base64;
use Getopt::Long;
use JSON;
use Getopt::Long;
use Data::Dumper;
use URI::Escape;

my $g_target = "127.0.0.1";
my $g_debug  = 0;

my $base64_string  = "vyatta:vyatta";
my $g_encoded_auth = encode_base64($base64_string);
chop($g_encoded_auth);

my ($cmd, $access, $ip);

#
#
#
#
sub _op_post {
    my $cmd = shift;

    if (!defined $cmd || $cmd eq '') {
        return 1;
    }

    if (!defined $g_target) {
        return 1;
    }
    $cmd =~ s/\//%2F/g;
    $cmd = join "\/", (split(" ", $cmd));
    my $process_id;

    #test that we can push an op mode request into the bg
    my $httpcmd =
"curl -k -s -i -H \"authorization: Basic $g_encoded_auth\"  -H \"content-length:0\"  -X POST https://$g_target/rest/op/$cmd";
    my @out = `$httpcmd`;
    foreach my $out (@out) {
        if ($out =~ /^HTTP\/[\d.]+\s+(\d+)\s+.*$/) {
            my $code = $1;

            if ($code !~ /201/) {
                if ($g_debug == 1) {
                    printf(
"\nError on response: $code\n For this command: $httpcmd\n"
                    );
                }
                return 1;
            }
        }
        elsif ($out =~ /^Location:/) {
            my @a = split(" ", $out);
            my @b = split("/", $a[1]);
            $process_id = $b[2];
        }
    }
    if (!defined $process_id) {
        if ($g_debug == 1) {
            printf("Process ID not found for this command: $httpcmd\n");
        }
        return 1;
    }

    if ($g_debug == 1) {
        print("$httpcmd\n");
    }

    #now start retrieving the values
    my $ct = 0;
    while ($ct < 10) {
        my $uri = "https://$g_target/rest/op/$process_id";

        my ($code, $body) = send_request("GET", $uri, 1);
        if ($code =~ /200/) {

            #don't do anything here
        }
        elsif ($code =~ /202/) {
            sleep(2);
            next;
        }
        elsif ($code =~ /410/) {
            return 0;
        }
        else {
            if ($g_debug == 1) {
                printf("unexpected return code: $code\n");
            }
            return 1;
        }

        if (defined $body) {
            print("$body");
        }
        ++$ct;
    }
    return 0;
}

#
#
#
#
sub send_request {
    my $http_method   = shift;
    my $http_uri      = shift;
    my $override_json = shift;

    my $code = 200;
    my $body;
    my $cmd =
"curl -k -s -i -H \"authorization: Basic $g_encoded_auth\"  -H \"content-length:0\"  -X $http_method $http_uri";

    my @out = `$cmd`;
    foreach my $out (@out) {
        if ($out =~ /^HTTP\/[\d.]+\s+(\d+)\s+.*$/) {
            $code = $1;
        }
        elsif ($out =~ /^\r/ || defined $body) {
            $body .= $out;
        }
    }

    if ($g_debug) {
        print("\nCOMMAND: $cmd \n");
    }

    #let's convert the body to json, unless requested not to
    if (defined $body && $body !~ /^\r$/) {
        if ($g_debug) {
            print("\nBODY: $body \n");
        }

        if ($override_json == 1) {
            return ($code, $body);
        }
        else {
            my $result;
            eval { $result = from_json($body); };
            if ($@) {
                $result = undef;
            }
            return ($code, $result);
        }
    }
    return ($code, undef);
}

##########################################################################
#
# start of main
#
# Handles both easy and expert modes
#
##########################################################################
sub usage() {
    print "       $0 --command=command --server=ip --access=[user:pswd]\n";
    exit 0;
}

#pull commands and call command
GetOptions(
    "server=s"  => \$ip,
    "command=s" => \$cmd,
    "access:s"  => \$access,
) or usage();

if (!defined $ip || !defined $cmd) {
    usage();
    exit 0;
}

$g_target = $ip;
if (defined $access) {
    $g_encoded_auth = encode_base64($access);
    chop($g_encoded_auth);
}

_op_post($cmd);

exit 0;
