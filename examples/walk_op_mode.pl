#!/usr/bin/perl
#
# Module: walk_op_mode.pl
# Description: Script to use rest api to walk op mode commands.
# 
# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2017 by Brocade Communications Systems, Inc.
# All Rights Reserved.
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
my $start_path = "show";
my $ua;

my $op_cmds_run     = 0;
my $op_cmds_skipped = 0;
my $op_cmds_stopped = 0;

sub end_op_request {
    my ($url, $msg) = @_;

    print $msg if defined $msg;
    $op_cmds_stopped++;
    my $request = HTTP::Request->new(DELETE => $url);
    my $response = $ua->request($request);
    return if $response->is_success;
    print "Error delete [$url] - $response->status_line";
}

sub read_op_output {
    my ($location, $limit) = @_;
    
    my $url = "https://$target/$location";
    my ($response, $output, $count);
    $count = 0;
    do {
        $response = $ua->get($url);
        if ($response->is_success) {
            $output = $response->content;
            $output =~ s/[\x00-\x08\x0B-\x1F\x7F-\xFF]//g; # strip unprintable
            print $output;
            if ($output eq '') {
                if ($count++ > 10) {
                    end_op_request($url, "\nNo new output - Stopping\n");
                    return;
                }
            }
            if ($limit) {
                if (--$limit == 0) {
                    end_op_request($url, "\nLimit exceeded - Stopping\n");
                    return;
                }
            }
        } else {
            if ($response->code != 410) {
                print "Failed to GET [$url]: ", $response->status_line;
                return;
            }
        }
    } while ($response->code != 410);
}

my @skip_cmds = ('/clear/https/process',
                 '/clear/connection-tracking',
                 '/configure',
                 '/conntect',
                 '/disconnect',
                 '/install-image',
                 '/install-system',
                 '/reboot',
                 '/reboot/now',
                 '/ping',
                 '/ping6',
    );

my %skip_hash = map {$_ => 1} @skip_cmds;
                 
sub should_skip {
    my ($path) = @_;

    return $skip_hash{$path};
}

sub run_op_cmd {
    my ($path) = @_;

    if (should_skip($path)) {
        print "Skipping [$path]\n\n";
        return;
    }

    print "running [$path]\n";
    my $url = "$base_url/op/$path";
    my $response = $ua->post($url);
    my $limit = 0;
    if ($path =~ /capture$/) {
        $limit = 20;
    }
    if ($response->is_success) {
        my $location = $response->header('Location');
        if (defined $location) {
            read_op_output($location, $limit);
            print "\n";
            $op_cmds_run++;
        } else {
            print "No location found\n";
        }
    } else {
        print "Failed to GET [$url]: ", $response->status_line;        
    }
}

sub get_op_enums {
    my ($path) = @_;

    my @nodes = ();
    my $url  = "$base_url/op/$path/";
    my $response = $ua->get($url);
    if ($response->is_error) {
        return @nodes if $response->code == 404;
        print "Failed to GET [$url]: ", $response->status_line;
        return @nodes;
    }
     
    if ($response->header('content-type') eq 'application/json') {
        my $perl_scalar = decode_json($response->content);
        my $enums       = $perl_scalar->{enum};
        push @nodes, @$enums if defined $enums;
    }
    return @nodes;
}

sub get_op_children {
    my ($path) = @_;

    my @nodes = ();
    my $url  = "$base_url/op/$path/";
    my $response = $ua->get($url);
    if ($response->is_error) {
        return @nodes if $response->code == 404;
        print "Failed to GET [$url]: ", $response->status_line;
        return @nodes;
    }
     
    if ($response->header('content-type') eq 'application/json') {
        my $perl_scalar = decode_json($response->content);
        my $children = $perl_scalar->{children};
        my $action   = $perl_scalar->{action};
        if (defined $action and $action eq "true") {
            if ($path =~ /\*/) {
                print "skipping [$path]\n\n";
                $op_cmds_skipped++;
            } else {
                run_op_cmd($path);
            }
        }
        if (defined $children) {
            push @nodes, @$children;
        }
    }
    return @nodes;
}

sub get_op_cmds {
    my ($path) = @_;

    my @outs = get_op_children($path);
    foreach my $out (@outs) {
        if ($out eq '*') {
            my @enums = get_op_enums("$path/$out");
            foreach my $enum (@enums) {
                next if $enum =~ m/[<|>]/;
                get_op_cmds("$path/$enum");
            }
        } else {
            get_op_cmds("$path/$out");
        }
    }
}  

sub exit_stats {
    print "\nTotals:\n";
    print   "=======\n";
    print "Ran    : $op_cmds_run\n";
    print "Skipped: $op_cmds_skipped\n";
    print "Stopped: $op_cmds_stopped\n\n";
    
    if ($op_cmds_run) {
        print "Check for left over processes\n";
        my $url = "$base_url/op";
        my $response = $ua->get($url);
        if ($response->is_success) {
            my $content = $response->content;
            if ($content ne '') {
                print $response->content;
            } else {
                print "No left over processes\n";
            }
        } else {
            print "Failed to GET [$url]: ", $response->status_line;        
        }
    }

    exit 0;
}


# main

$target     = $ARGV[0] if defined $ARGV[0];
$user       = $ARGV[1] if defined $ARGV[1];
$passwd     = $ARGV[2] if defined $ARGV[2];
$start_path = $ARGV[3] if defined $ARGV[3];
$base_url   = "https://$target/rest";

print "target     [$target]\n";
print "start path [$start_path]\n\n";

$SIG{'INT'} = 'exit_stats';

$ua = LWP::UserAgent->new;
my $auth = encode_base64("$user:$passwd");
$ua->default_header('content-length' => 0);
$ua->default_header("authorization" => "Basic $auth");

get_op_cmds($start_path);   # do the real work

exit_stats();

# end of file
