#!/usr/bin/perl
#
# Module: router_backup.pl
# 
# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2017 by Brocade Communications Systems, Inc.
# All Rights Reserved.
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

sub write_file_value {
    my ($file, $value) = @_;

    open my $F, '>', $file or die "Error: opening [$file] -$!.";
    print $F "$value";
    close $F;
}

sub git_update {
    my ($git_dir, $router, $version, $config) = @_;

    $git_dir = "$git_dir/$router";
    my $repo;
    if (! -e $git_dir) {
        mkdir($git_dir) or die "Error creating directory [$git_dir] - $!";
        chdir($git_dir);
        print "Creating git repo [$git_dir]\n";
        system("git init");
        $repo = Git->repository(Directory => $git_dir);
        die "Error opeing repo [$repo] - $!" unless $repo;

        write_file_value("$git_dir/version", $version);
        write_file_value("$git_dir/config.boot", $config);
        $repo->command('add', '.');
        $repo->command('commit', '-m Initial comment');
        return;
    }
    
    $repo = Git->repository(Directory => $git_dir);
    write_file_value("$git_dir/version", $version);
    write_file_value("$git_dir/config.boot", $config);

    print "Checking for changes.\n";
    my $output = $repo->command('diff');
    if (! defined $output or $output eq '') {
        print "No changes.\n";
        return;
    }
    print $output;

    print "Committing changes to [$git_dir]\n";
    my $date = strftime('%b %e, %Y', localtime);
    $repo->command('commit', '-a', "-m $date backup");
    return;
}

sub backup_config {
    my ($router, $auth, $git_dir) = @_;
    
    my ($cli, $err, $output, $show_version, $config);
    print "Starting config backup of [$router]\n";

    $cli = RestClient->new();  
    $err = $cli->auth_base64($router, $auth);
    if ($err) {
        print "Authorization error - $err\n";
        return;
    }
    ($err, $output) = $cli->run_op_cmd('show version all');
    print "Error getting 'show verion' - $err\n" if defined $err;
    $show_version = $output if defined $output;
    $show_version =~ s/^Uptime:.*$//m;   # strip uptime

    ($err, $output) = $cli->run_op_cmd('show configuration');
    print "Error getting 'show configuration' - $err\n" if defined $err;
    $config = $output if defined $output;

    if (defined $show_version and defined $config) {
        print "Sucessfully retrieved config.\n";
        git_update($git_dir, $router, $show_version, $config);
    }
}

sub usage {
    print "Usage: $0 --routers-file=<file> --git-dir=<dir>\n\n";
    exit 1;
}


#
# main
#

my ($routers_file, $git_dir);

GetOptions("routers-file=s" => \$routers_file,
           "git-dir=s"      => \$git_dir,
          );

usage() unless $routers_file;
usage() unless $git_dir;

if (! -e $git_dir) {
    mkdir($git_dir) or die "Error creating directory [$git_dir] - $!";
}

my %router_hash = read_router_file($routers_file);

foreach my $router (keys %router_hash) {
    backup_config($router, $router_hash{$router}, $git_dir);
    print "\n";
}
exit 0;

# end of file


