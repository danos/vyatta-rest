#!/usr/bin/perl
#
# Module: add_conf2.pl
# Description: 2nd version of add_conf.pl that uses client api
# 
# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2017 by Brocade Communications Systems, Inc.
# Copyright (c) 2009-2010 Vyatta, Inc.
# All Rights Reserved.
# 
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use warnings;

use lib '../lib';
use Vyatta::RestClient;

my $target     = '127.0.0.1';
my $base_url   = "https://$target/rest";
my $user       = "vyatta";
my $passwd     = "vyatta";
my $ua;
my $response;
my $cmd;

# main

$target     = $ARGV[0] if defined $ARGV[0];
$user       = $ARGV[1] if defined $ARGV[1];
$passwd     = $ARGV[2] if defined $ARGV[2];
$cmd        = $ARGV[3] if defined $ARGV[3];

my ($cli, $err, $output);

$cli = RestClient->new(); 
$err = $cli->auth($target, $user, $passwd);
if ($err) {
    print "auth - $err\n";
    $cli->configure_exit_discard();
    exit 1;
}

print "Entering config mode on $target\n";
$err = $cli->configure();
print "configure - $err\n" if $err;

print "Issuing [$cmd]\n";
$err = $cli->set($cmd);
if ($err) {
    print "set - $err\n";
    $cli->configure_exit_discard();
    exit 1;
}

print "commit\n";
$err = $cli->commit();
if ($err) {
    print "commit - $err\n";
    $cli->configure_exit_discard();
    exit 1;
}

print "save\n";
$err = $cli->save();
print "save - $err\n" if $err;

print "exit config mode\n";
$err = $cli->configure_exit();
print "configure_exit - $err\n" if $err;

