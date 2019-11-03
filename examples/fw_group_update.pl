#!/usr/bin/perl
#
# Module: fw_group_update.pl
# Description: Script to update a firewall group on remote routers.
# 
# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2017 by Brocade Communications Systems, Inc.
# All rights reserved.
# Copyright (c) 2010 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use warnings;

use POSIX;
use Getopt::Long;
use MIME::Base64;
use Git;

use lib '../lib';
use Vyatta::RestClient;


sub read_router_file {
    my ($file) = @_;

    my %router_hash = ();
    open(my $FILE, "<", $file) or die "Error: opening [$file] $!";
    while (<$FILE>) {
        next if m/^\#/;
        last unless m/([^\s]+)\s+([^\s]+)\s+([^\s]+).*/;
        my $auth = encode_base64("$2:$3");
        $router_hash{$1} = $auth;
    }
    close($FILE);
    return %router_hash;
}

sub read_group_file {
    my ($file) = @_;

    my %group_hash = ();
    open(my $FILE, "<", $file) or die "Error: opening [$file] $!";
    while (<$FILE>) {
        next if m/^\#/;
        last unless m/(\d+\.\d+\.\d+\.\d+\/\d+).*/;
        $group_hash{$1} = 1;
    }
    close($FILE);
    return %group_hash;
}

sub get_configured_values {
    my ($cli, $group) = @_;
    
    my @nodes = ();
    my ($err, $output) = $cli->run_op_cmd("show firewall group $group");
    print "show - $err\n" if defined $err;    
    my @lines = split("\n", $output);
    foreach my $line (@lines) {
        if ($line =~ m/(\d+\.\d+\.\d+\.\d+\/\d+)/) {
            push @nodes, $1;
        }
    }
    my %network_hash = map {$_ => 1} @nodes;
    return %network_hash;
}


my $set_adds = 0;
my $set_errs = 0;
my $del_adds = 0;
my $del_errs = 0;

sub add_conf_cmd {
    my ($cli, $action, $path, $should_commit) = @_;

    my $err;
    my $cmd = "$action $path";
    if ($action eq 'set') {
        $set_adds++;
        $err = $cli->set($cmd);
        print "set error [$cmd] - $err\n" if defined $err;
        $set_errs++ if defined $err;
    } elsif ($action eq 'delete') {
        $del_adds++;
        $err = $cli->set($cmd);
        print "delete error [$cmd] - $err\n" if defined $err;
        $set_errs++ if defined $err;
    } else {
        print "Unknown command [$action]\n";
        return;
    }

    my $uncommitted = $cli->uncommitted();
    if ($uncommitted > 0 and $uncommitted % $should_commit == 0) {
        $err = $cli->commit();
        print "Error - $err\n" if defined $err;
    }
    return;
}

sub update_group {
    my ($router, $auth, $group, %group_hash) = @_;

    print "update_group [$group] on [$router]\n";
    
    my ($cli, $err, $output);

    $cli = RestClient->new();  
    $err = $cli->auth_base64($router, $auth);
    if ($err) {
        print "Authorization failed - $err\n";
        return;
    }

    my %network_hash = get_configured_values($cli, $group);

    my $cmd = "firewall group network-group $group network";

    my $nodes_pre   = keys (%network_hash);
    my $group_count = keys (%group_hash);
    print "FW group [$group] = $group_count entries, configured $nodes_pre\n";

    my $start_time = time;

    $cli->configure();
    
    # check for additions
    foreach my $net (keys %group_hash) {
        add_conf_cmd($cli, 'set', "$cmd $net", 100) 
            if ! defined $network_hash{$net};
    }

    # check for deletions
    foreach my $net (keys %network_hash) {    
        add_conf_cmd($cli, 'delete', "$cmd $net", 100) 
            if ! defined $group_hash{$net};
    }
    
    if ($cli->uncommitted() > 0) {
        $err = $cli->commit();
        if ($err) {
            print "Error - $err\n" if defined $err;
            $cli->configure_exit_discard();
            return;
        }
    }
    $err = $cli->save();
    print "save - $err\n" if defined $err;
    $cli->configure_exit();

    my $end_time = time;

    print "\nRun time  : ", ($end_time - $start_time), "\n";
    print "Additions : $set_adds\n";
    print "Add errors: $set_errs\n";
    print "Deletions : $del_adds\n";
    print "Del errors: $del_errs\n";

    return;
}


sub usage {
    print "Usage: $0 --routers-file=<file> --group-name=<group> "
          . "--group-file<file>\n\n";
    exit 1;
}


#
# main
#

my ($routers_file, $fw_group_name, $fw_group_file);

GetOptions("routers-file=s" => \$routers_file,
           "group-name=s"   => \$fw_group_name,
           "group-file=s"   => \$fw_group_file,
          );

usage() unless $routers_file;
usage() unless $fw_group_name;
usage() unless $fw_group_file;

my %router_hash = read_router_file($routers_file);

my %group_hash  = read_group_file($fw_group_file);

foreach my $router (keys %router_hash) {
    update_group($router, $router_hash{$router}, $fw_group_name, %group_hash);
    print "\n";
}

exit 0;

# end of file
