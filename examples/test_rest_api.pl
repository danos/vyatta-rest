#!/usr/bin/perl
#
# Module: test_rest_api.pl
# Description: Script to show examples using Vyatta::RestApi.pm
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

use lib '../lib';

use Vyatta::RestClient;


die "Usage: $0 remote_ip <user> <password>\n"
    unless ( $#ARGV >= 0 );

my $target = '127.0.0.1';
my $user   = 'vyatta';
my $passwd = 'vyatta';

$target = $ARGV[0] if defined $ARGV[0];
$user   = $ARGV[1] if defined $ARGV[1];
$passwd = $ARGV[2] if defined $ARGV[2];

my ($cli, $cmd, $err_code, $err, $output, @nodes);

#
# get cli handle and authentication
#
$cli = RestClient->new();  

($err_code, $err) = $cli->test_connectivity($target, 1);
if (defined $err) {
    print "Error test_connectivity $err\n";
    exit 1;
}
print "test_connectity passed\n\n";

($err_code, $err) = $cli->auth($target, $user, $passwd);
if (defined $err) {
    print "Authorization $err\n";
    exit 1;
}
print "authorization passed\n\n";

# 
# Run op mode command
#
$cmd = "show version";
($err, $output) = $cli->run_op_cmd($cmd);
print "- run_op_cmd [$cmd]\n";
print "Error $err\n" if defined $err;
print $output, "\n"  if defined $output;

#
# Change conf mode
#
print "- changing host-name to 'uffda'\n";
# 1) enter configure mode
$err = $cli->configure();
print "configure error $err\n" if defined $err;

# 2) set/delete
$err = $cli->set('set system host-name uffda');
print "set error $err\n" if defined $err;

# 3) commit
$err = $cli->commit();
print "commit error $err\n" if defined $err;

# 4) save
$err = $cli->save();
print "save error $err\n" if defined $err;

# 5) exit
$err = $cli->configure_exit();
print "exit error $err\n" if defined $err;

# 6) verify change
print "- show host name\n";
($err, $output) = $cli->run_op_cmd('show host name');
print "show error $err\n" if defined $err;
print $output, "\n"       if defined $output;

#
# Run batch of conf mode cmds
#
print "- run batch conf mode\n";
my @conf_cmds = ('set system host-name r1',
                 'set system time-zone US/Pacific',
                 'set interfaces ethernet eth2 address 9.9.9.9/24',
                 'set interfaces ethernet eth2 address 2001:1::1/64',
                );

$cli->batch_conf_cmds(@conf_cmds);
print "batch error $err\n" if defined $err;

print "- show host name\n";
($err, $output) = $cli->run_op_cmd('show host name');
print "show error $err\n" if defined $err;
print $output, "\n"       if defined $output;

print "- test special characters (with debug on)\n";
$err = $cli->configure();
$cli->debug(1);
$err = $cli->set("set interfaces ethernet eth2 description 'wordspace'");
print "set error $err\n" if defined $err;
$cli->debug(0);
$err = $cli->commit();
print "commit error $err\n" if defined $err;

print "- show interfaces before eth2 address/description delete\n";
($err, $output) = $cli->run_op_cmd('show interfaces');
print "show error $err\n" if defined $err;
print $output, "\n"       if defined $output;

print "delete eth2 address/descripton\n";
$err = $cli->delete('delete interfaces ethernet eth2 address');
print "delete error $err\n" if defined $err;
$err = $cli->delete('delete interfaces ethernet eth2 description');
print "delete error $err\n" if defined $err;
my $uncommitted = $cli->uncommitted();
print "uncommitted cmds $uncommitted\n\n";
print "- config mode show\n";
($err, @nodes) = $cli->configure_show('service lldp interface all location');
print "configure_show error $err\n" if defined $err;
foreach my $node (@nodes) {
    print "node [$node]\n";
}
print "\n";

$err = $cli->commit;
print "commit error $err\n" if defined $err;
$cli->configure_exit;
print "show interfaces after eth2 address/description delete\n";
($err, $output) = $cli->run_op_cmd('show interfaces');
print $output, "\n" if defined $output;


#
# Error handling
#
print "Test error handling - should cause failures\n\n";

# 1) invalid op command
print "- check invalid op command 'show interfac ethernet eth0'\n";
($err, $output) = $cli->run_op_cmd('show interfac ethernet eth0');
print "show error $err\n" if defined $err;
print $output, "\n"       if defined $output;

# 2) invalid conf set without configure
print "\n- check invalid set without configure\n";
$err = $cli->set('set system host-name joe');
print "set error $err\n" if defined $err;

# 3) invalid set command
print "\n- check invalid conf command 'set system hostname bababoey'\n";
$err = $cli->configure();
print "set error $err\n" if defined $err;
$err = $cli->set('set system hostname bababoey');
print "set error $err\n" if defined $err;
$err = $cli->commit();
print "commit error $err\n" if defined $err;
$err = $cli->configure_exit();
print "exit error $err\n" if defined $err;

# 4) exit with uncommitted changes
print "\n- check exit with uncommitted changes\n";
$err = $cli->configure();
print "set error $err\n" if defined $err;
$err = $cli->set('set system host-name elephant-boy');
print "set error $err\n" if defined $err;
print "commit error $err\n" if defined $err;
$err = $cli->configure_exit();
print "exit error $err\n" if defined $err;
$err = $cli->configure_exit_discard();
print "exit discard error $err\n" if defined $err;

# 5) check authentication failure
print "\n- check authentication failure\n";
$cli = RestClient->new();  
$err = $cli->auth($target, 'vyatta', 'monkeyfart');
print "auth error $err\n" if $err;

# end of file
