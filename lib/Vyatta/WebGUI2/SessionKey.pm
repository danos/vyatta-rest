# Module: SessionKey.pm
# Description: used to generate session key 
#
# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2009-2010 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

use strict;
use warnings;

use POSIX;

use Data::Dumper;
use lib '/opt/vyatta/share/perl5';
use App::MapSimple;
use App::MsgSimple;
use NetAddr::IP;
use Time::HiRes qw(gettimeofday); 
use JSON;


my $lck_file = "/var/run/gui/session.lck";
my $tmp_file = "/var/run/gui/session_tmp";
my $sess_file = "/var/run/gui/session";

sub gen_key
{
    my ($src_ip) = @_;

    if (!defined($src_ip)) {
	exit(1); #don't generate, just fail...
    }

    my @octets = split(/\./, $src_ip);

    my $key;
    open FH, "/dev/urandom";
    my $string = <FH>;
    my @chars = split //,$string;
    if (!defined($chars[3])) {
	exit(1);
    }
    $key = sprintf("%02X%02X%02X%02X%02X%02X%02X%02X",
		   $octets[0],$octets[1],$octets[2],$octets[3],
		   ord($chars[0]),ord($chars[1]),ord($chars[2]),ord($chars[3]));
    close(FH);
    return $key;
}

sub get_key {
    my ($name, $access_level, $src_ip) = @_;

    if (!defined($name) || !defined($src_ip) || $name eq "" || $src_ip eq "") {
        exit(1);
    }
    
    ####################################################################
    ####################################################################
    #let's try five times before giving up
    my $try = 5;
    my $lck_fh;
    while ($try > 0) {
        if (sysopen(LCK_FH, $lck_file, O_WRONLY|O_EXCL|O_CREAT)) {
    	last;
        }
        Time::HiRes::usleep(50);
        $try--;
    }
    if ($try == 0) {
        unlink($lck_file);
        exit(1);
    }
    
    my $key = "";
    my $found = "false";
    #line will be "sessionid,username,timelastaccess,srcip
    if (sysopen(FH, $sess_file,O_RDWR|O_CREAT, 0666)) {
        if (sysopen(FH_TMP, $tmp_file,O_RDWR|O_CREAT, 0666)) {
    	while (<FH>) {
    	    my $line = $_;
    	    #check for source ip and username match
    	    my @session = split(",",$line);
    	    if ($#session != 4) {
    		next; #skip not a valid entry
    	    }
    	    chop($session[4]);
    
    	    if (($name eq $session[1]) && ($src_ip eq $session[3])) {
    		my ($epochseconds, undef) = gettimeofday;     
    		$key = $session[0];
    		print FH_TMP "$session[0],$name,$epochseconds,$src_ip,$access_level\n";
    		$found = "true"; #found, so let's update time only
    	    }
    	    else {
    		if ($line ne "") {
    		    print FH_TMP "$line\n";
    		}
    	    }
    	}
        }
        else {
    	unlink($lck_file);
    	exit(1);
        }
    }
    else {
        unlink($lck_file);
        exit(1);
    }
    
    if ($found eq "false") {
        #webgui 1 uses ip+username to differentiate unique session
        $key = gen_key($src_ip);
    #    $key = sprintf("%04X%04X", int(rand(0x10000)), int(rand(0x10000)));
        my ($epochseconds, undef) = gettimeofday;     
        print FH_TMP "$key,$name,$epochseconds,$src_ip,$access_level\n"; #create new entry
    }
    close(FH_TMP);
    close(FH);
    rename($tmp_file,$sess_file);
    unlink($tmp_file);
    close(LCK_FH);
    unlink($lck_file);
    
    my $root=();
    $root->{session}->{user} = $name;
    $root->{session}->{source} = $src_ip;
    $root->{session}->{key} = $key;
    
    print to_json($root, {pretty => 1});
    
    exit(0);
}

1;
