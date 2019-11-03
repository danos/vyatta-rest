#!/usr/bin/perl
#
# Module: add_conf.pl
# Description: Script to use rest api to add a config mode command
# 
# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2017 by Brocade Communications Systems, Inc.
# Copyright (c) 2009-2010 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use warnings;

use POSIX;
use JSON;
use MIME::Base64;
use Getopt::Long;
use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request;

my $target     = '127.0.0.1';
my $base_url   = "https://$target/rest";
my $user       = "vyatta";
my $passwd     = "vyatta";
my $ua;
my $response;
my $cmd;

sub end_request {
    my ($url, $msg) = @_;

    print $msg if defined $msg;
    my $request = HTTP::Request->new(DELETE => $url);
    my $response = $ua->request($request);
    return if $response->is_success;
    print "Error delete [$url] - $response->status_line";
}

# main

$target     = $ARGV[0] if defined $ARGV[0];
$user       = $ARGV[1] if defined $ARGV[1];
$passwd     = $ARGV[2] if defined $ARGV[2];
$cmd        = $ARGV[3] if defined $ARGV[3];
$base_url   = "https://$target/rest/conf";


my $auth = encode_base64("$user:$passwd");

$ua = LWP::UserAgent->new();  
$ua->default_header('content-length' => 0);
$ua->default_header("authorization" => "Basic $auth");

my $url = "$base_url";
$response = $ua->post($url);
if ($response->is_error) {
    die "Error entering conf mode - ", $response->status_line , "\n";
}
print "Entering config mode on $target\n";

my $location = $response->header('Location');

$cmd =~ s/ /\//g;

$url = "https://$target/$location/$cmd";
my $request = HTTP::Request->new(PUT => $url);
$response = $ua->request($request);
if ($response->is_error) {
    die "Error put command [$url] - ", $response->status_line , "\n";
}

$url = "https://$target/$location/commit";

$response = $ua->post($url);
if ($response->is_error) {
    die "Error post commit - ", $response->status_line , "\n";
}
print "Commit successful\n";

end_request("https://$target/$location", "DONE\n");
