#!/usr/bin/perl
#
# Module: vyatta-webgui2-shell.pl
# Description: vyatta-webgui2-shell sample
#
# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2014 by Brocade Communications Systems, Inc.
# All rights reserved.
# Copyright (c) 2009-2013 Vyatta, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use warnings;
use lib "/opt/vyatta/share/perl5/";
use Term::ReadKey;
use POSIX;
use MIME::Base64;
use JSON;
use Getopt::Long;
use Data::Dumper;
use URI::Escape;

my $g_target = '127.0.0.1';
my $g_mode   = 'op';
my $g_conf_id;
my $g_debug = 0;
my @history;

my $base64_string  = "vyatta:vyatta";
my $g_encoded_auth = encode_base64($base64_string);
chop($g_encoded_auth);

#
#
#
#
sub _config_get {
    my $cmd = shift;

    if (!defined $g_target) {
        return (1, undef);
    }

    if (defined $cmd && defined $g_conf_id) {
        my $last_elem = undef;

        #let's lop off the first entry (either a set or delete)
        my @cmd = split(" ", $cmd);
        if (   $cmd[0] ne 'set'
            && $cmd[0] ne 'delete'
            && $cmd[0] ne 'comment'
            && $cmd[0] ne 'activate'
            && $cmd[0] ne 'deactivate')
        {
            return (1, undef);
        }

        my $action = shift(@cmd);

        for my $list_item (@cmd) {
            $list_item =~ s/\//%2F/g;
        }
        my $cmd2 = join "\/", @cmd;

        my $uri = "https://$g_target/rest/conf/$g_conf_id/$cmd2";
        my ($code, $params) = send_request("GET", $uri, 0);
        my $body;
        if ($code !~ /200/) {

            #lop off the last entry and retry
            $last_elem = pop(@cmd);
            $cmd = join "\/", @cmd;

            $uri = "https://$g_target/rest/conf/$g_conf_id/$cmd";
            ($code, $params) = send_request("GET", $uri, 0);

            if ($code =~ /200/) {
                if (defined $params) {

  #TODO: add partial matched set returned, just as we do with op mode cmd now...

#do we have enough for a partial match?
#take last element on array and look for most specific full match and return full path, otherwise partial completion
                    if (defined $last_elem) {
                        my $n_match = 0;
                        my $match_word;
                        if (defined $params->{children}) {
                            my @m = @{ $params->{children} };
                            foreach my $v (@m) {
                                if (index($v->{'name'}, $last_elem) == 0) {
                                    $match_word = $v->{'name'};
                                    $n_match++;
                                }
                            }
                        }
                        if (defined $params->{enum}) {
                            my @m = @{ $params->{enum} };
                            foreach my $v (@m) {
                                if (index($v, $last_elem) == 0) {
                                    $match_word = $v;
                                    $n_match++;
                                }
                            }
                        }

                        if ($n_match == 1) {
                            my $new_cmd;
                            if ($#cmd == -1) {
                                $new_cmd = $action . " " . $match_word . " ";
                            }
                            else {
                                $new_cmd =
                                    $action . " "
                                  . join(" ", @cmd) . " "
                                  . $match_word . " ";
                            }
                            return (0, $new_cmd);
                        }
                    }
                }
            }
        }

  #handle special case where there is a single possible match on an empty string
        my $only_element = undef;
        if (defined $params->{children}) {

            #need to make array out of $params->{children}->{name}
            my @m = @{ $params->{children} };
            if ($#m == 0) {
                $only_element = $m[0]->{'name'};
            }
        }

        if (defined $params->{enum} && !defined $only_element) {
            my @m = @{ $params->{enum} };
            if ($#m == 0) {
                $only_element = $params->{elem};
            }
        }

        if (defined $only_element) {
            my $new_cmd =
              $action . " " . join(" ", @cmd) . " " . $only_element . " ";
            return (0, $new_cmd);
        }

        printf("\nPOSSIBLE COMPLETIONS:\n");
        if (defined $params->{children}) {
            my @procs = @{ $params->{children} };
            @procs = sort { $a->{'name'} cmp $b->{'name'} } @procs;
            foreach my $p (@procs) {
                if (defined $last_elem) {
                    my $foo = index($p->{'name'}, $last_elem);
                    if ($foo == 0) {
                        printf("$p->{'name'}\n");
                    }
                }
                else {
                    printf("$p->{'name'}\n");
                }
            }
        }
        if (defined $params->{enum}) {
            my @procs = @{ $params->{enum} };
            @procs = sort(@procs);
            foreach my $p (@procs) {
                if (defined $last_elem) {
                    my $foo = index($p->{'name'}, $last_elem);
                    if ($foo == 0) {
                        printf("$p\n");
                    }
                }
                else {
                    printf("$p\n");
                }
            }
        }
        if (defined $params->{type}) {
            my @types = @{ $params->{type} };
            foreach my $t (@types) {
                if ($t ne 'none') {
                    printf("<$t>");
                    if (defined $params->{help}) {
                        printf(" $params->{help}");
                    }
                    if (defined $params->{comp_help}) {
                        printf("\n$params->{comp_help}");
                    }
                    printf("\n");
                }
            }
            if (defined $params->{val_help}) {
                my @val_help = @{ $params->{val_help} };
                foreach my $vh (@val_help) {
                    printf("\n  $vh->{type}\t$vh->{vals}\t$vh->{help}");
                }
            }
        }
        if (!defined $params->{children} && !defined $params->{enum}) {
            return (1, undef);
        }
    }
    else {
        my $uri = "https://$g_target/rest/conf";
        my ($code, $params) = send_request("GET", $uri, 0);
        if ($code =~ /200/) {
            if (defined $params && defined $params->{session}) {
                my @procs = @{ $params->{session} };
                @procs = sort { $a->{'started'} <=> $b->{'started'} } @procs;
                printf(
"\nusername\tid\t\t\tstarted\t\t\tupdated\t\tmodified\tdescription\n"
                );
                foreach my $p (@procs) {
                    my $s = POSIX::strftime('%H:%M %d.%m.%y',
                        localtime($p->{'started'}));
                    my $u = POSIX::strftime('%H:%M %d.%m.%y',
                        localtime($p->{'updated'}));
                    printf(
"$p->{'username'}\t\t$p->{'id'}\t$s\t\t$u\t$p->{'modified'}\t\t$p->{'description'}\n"
                    );
                }
            }
        }
        else {
            return (1, undef);
        }
    }
    return (0, undef);
}

#
#
#
#
sub _config_put {
    my $status = 0;
    my $cmd    = shift;
    if (!defined $g_conf_id) {
        return 1;
    }

    if (!defined $cmd || $cmd eq '') {
        return 1;
    }

    # convert spaces to slashes, unless enclosed by quotes
    my @items = ($cmd =~ /(".*?"|\S+)/g);

    #    $cmd =~ s/ /\//g;
    #convert any forward slashes in items into escaped values
    for my $list_item (@items) {
        $list_item =~ s/\//%2F/g;
    }
    my $rest_cmd = join("/", @items);
    $rest_cmd =~ s/ /%20/g;
    $rest_cmd =~ s/\"//g;

    #    print $encoded_rest_cmd. "\n";

    #now eat quotes
    #convert spaces to %20F

    my $uri = "https://$g_target/rest/conf/$g_conf_id/$rest_cmd";

    my ($code, $params) = send_request("PUT", $uri, 1);
    if ($code =~ /200/) {
        $status = 0;
    }
    else {
        $status = 1;
    }
    return $status;
}

#
#
#
#
sub _config_delete {
    my $status = 0;
    my $proc   = shift;
    if (!defined $proc) {
        return 1;
    }

    my $uri = "https://$g_target/rest/conf/$proc";

    my ($code, $params) = send_request("DELETE", $uri, 0);
    if ($code =~ /200/) {
        $status = 0;
    }
    else {
        $status = 1;
    }
    return $status;
}

#
#
#
#
sub _config_post {
    my $body;
    my $cmd = shift;
    my @out;
    if ($cmd =~ /configure/) {
        my (undef, $desc) = split(" ", $cmd);
        my $s_cmd =
"curl -k -s -i -H \"authorization: Basic $g_encoded_auth\"  -H \"content-length:0\" -X POST https://$g_target/rest/conf";
        if (defined $desc) {
            $s_cmd .= "/$desc";
        }

        $g_conf_id = undef;
        @out       = `$s_cmd`;

        #now let's extract the conf_id and set
        foreach my $out (@out) {
            if ($out =~ /^Location:/) {
                my @a = split(" ", $out);
                my @b = split("/", $a[1]);
                $g_conf_id = $b[2];
            }
        }
        if ($g_debug == 1) {
            printf("cmd: $s_cmd\n");
            if (defined $g_conf_id) {
                printf("Entered conf mode with id: $g_conf_id\n");
            }
            else {
                printf("no configuration id found\n");
            }
        }
        if (defined $g_conf_id) {
            return 0;
        }
        return 1;
    }
    else {

        #execute action
        if (!defined $g_conf_id) {
            return 1;
        }

        $cmd = join "\/", (split(" ", $cmd));
        my $s_cmd =
"curl -k -s -i -H \"authorization: Basic $g_encoded_auth\"  -H \"content-length:0\" -X POST https://$g_target/rest/conf/$g_conf_id/$cmd";
        @out = `$s_cmd`;
        if ($g_debug == 1) {
            printf("$s_cmd\n");
        }
    }
    my $status = 1;
    foreach my $out (@out) {
        if ($out =~ /^HTTP\/[\d.]+\s+(\d+)\s+.*$/) {
            if ($1 =~ /200/) {
                $status = 0;
            }
        }
        elsif ($out =~ /^\r/ || defined $body) {
            $body .= $out;
        }
    }

    #convert to flat string
    if (defined $body && $body ne '') {

        #	printf $body;
        #	substr $body, 0, 2, "" ;

#hack to be able to validate the json with embedded curly braces, needs to be without newlines.
#therefore replacing newlines with special character, validating, then replacing them back
#again with newlines.--not pretty
        my $orig_body = $body;

        #	$body =~ s/\n/craj/g;
        my $params;
        eval { $params = from_json($body); };
        if ($@) {
        }
        if (defined $params && defined $params->{message}) {
            my $body2 = $params->{message};

            #	    $body2 =~ s/craj/\n/g;
            if (defined $body2) {
                printf("\n" . $body2 . "\n");
            }
            my $err = $params->{error};
            if (defined $err) {
                printf("\n" . $err . "\n");
            }

        }
        else {
            printf($orig_body);
        }
    }

    return $status;
}

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
sub _op_get {
    my $input = shift;

    if (!defined $g_target) {
        return (1, undef);
    }

    if (!defined $input || $input eq '') {
        my $body;
        my $uri = "https://$g_target/rest/op";
        my ($code, $params) = send_request("GET", $uri, 0);
        if ($code !~ /200/) {
            return (1, undef);
        }
        if (defined $params && defined $params->{process}) {
            my @procs = @{ $params->{process} };
            @procs = sort { $a->{'start-time'} <=> $b->{'start-time'} } @procs;
            printf("\nusername\tstart-time\t\tid\t\t\tcommand\n");
            foreach my $p (@procs) {
                my $s = POSIX::strftime('%H:%M %d.%m.%y',
                    localtime($p->{'start-time'}));

   #		my $u = POSIX::strftime('%H:%M %d.%m.%y', localtime($p->{'last-update'}));
                printf(
                    "$p->{'username'}\t\t$s\t\t$p->{'id'}\t$p->{'command'}\n");
            }
        }
        return (0, undef);
    }
    else {

        #config get help at this point
        my $body;

        $input =~ s/\//%2F/g;
        my @cmd = split(" ", $input);
        my $cmd = join "\/", @cmd;

        my $last_elem = undef;

        my $uri = "https://$g_target/rest/op/$cmd";
        my ($code, $params) = send_request("GET", $uri, 0);
        if ($code !~ /200/) {

            if (!defined $params) {

                #lop off the last entry and retry
                $last_elem = pop(@cmd);
                $cmd = join "\/", @cmd;

                $uri = "https://$g_target/rest/op/$cmd";
                ($code, $params) = send_request("GET", $uri, 0);

                #let's attempt partial matching here
                if ($code =~ /200/) {
                    if (defined $params && defined $params->{children}) {

#do we have enough for a partial match?
#take last element on array and look for most specific full match and return full path, otherwise partial completion
                        if (defined $last_elem) {
                            my @m = @{ $params->{children} };
                            my $new_cmd;
                            my $n_match = 0;
                            my @match_set;
                            foreach my $v (@m) {
                                if (index($v, $last_elem) == 0) {
                                    if ($#cmd == -1) {
                                        $new_cmd = $v . " ";
                                    }
                                    else {
                                        $new_cmd =
                                          join(" ", @cmd) . " " . $v . " ";
                                    }

                                    push(@match_set, $v);
                                    $n_match++;
                                }
                            }
                            if (defined $new_cmd && $n_match == 1) {
                                return (0, $new_cmd);
                            }
                            else {
                                if ($#cmd != -1)
                                { #let's show all for the first command since there is no other way to see this.
                                    @{ $params->{children} } = @match_set;
                                }

                                #reset children for best match
                            }
                        }
                    }
                }
            }
        }

        #no match, then we'll return normal completion stuff
        if (defined $params && defined $params->{help}) {
            printf("\nHELP: $params->{help}\n");
        }

        #first find if $last_elem is present and enum is defined.
        if (defined $params->{enum}) {
            $last_elem = pop(@cmd);
            if (!grep { $_ eq $last_elem } @{ $params->{enum} }) {
                my @procs = @{ $params->{enum} };
                @procs = sort(@procs);
                printf("\nPOSSIBLE VALUES:\n");
                foreach my $p (@procs) {
                    printf("$p\n");
                }
                return (0, undef);
            }
        }

        if (defined $params->{children}) {
            my @procs = @{ $params->{children} };
            @procs = sort(@procs);
            printf("\nPOSSIBLE COMPLETIONS:\n");
            foreach my $p (@procs) {
                printf("$p\n");
            }
        }
        return (0, undef);
    }
}

#
#
#
#
sub _op_delete {
    my $status = 0;
    my $proc   = shift;
    if (!defined $proc) {
        return 1;
    }

    my $uri = "https://$g_target/rest/op/$proc";

    my ($code, $params) = send_request("DELETE", $uri, 0);
    if ($code =~ /200/) {
        $status = 0;
    }
    else {
        $status = 1;
    }
    return $status;
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

#
#
#
#
#
sub _show_rest {
    printf("\nconfigured servers:\n");
    printf("\t$g_target\n");
    if ($g_debug == 1) {
        printf("\tDEBUG MODE\n");
    }
    if ($g_mode eq 'conf') {
        printf("\tconf id: $g_conf_id\n");
    }
    printf("\tuser: $base64_string\n");
}

#
#
# Main entry point
#
#
#
open(TTY, "</dev/tty");
printf("$g_target:$g_mode> ");

while () {
    my $last_char     = '';
    my $input         = '';
    my $history_index = 0;
    while (1) {
        ReadMode("raw");
        my $in = ReadKey(0, *TTY);
        ReadMode("normal");

        #	printf "\nYou said %s, char number %03d\n",$in, ord $in;
        my $charkey = ord $in;
        if ($charkey == 9) {    #TAB
            if ($input =~ /^rest/) {
                printf("\nserver [target]\n");
                printf("proc\n");
                printf("debug\n");
                printf("history\n");
                printf("nodebug\n");
                printf("user [user:passwd]\n");
                printf("show\n");
            }
            elsif ($input =~ /^$/) {
                if ($g_mode eq 'conf') {
                    printf("\nset\n");
                    printf("delete\n");
                    printf("show\n");
                    printf("show-all\n");
                    printf("commit\n");
                    printf("save\n");
                    printf("load\n");
                    printf("merge\n");
                    printf("exit\n");
                    printf("rest\n");
                }
                else {
                    printf("show\n");
                    printf("others...\n");
                    printf("rest\n");
                }
            }
            else {
                if ($g_mode eq 'conf') {
                    my ($e, $suggested_input) = _config_get($input);
                    if ($e == 0 && defined $suggested_input) {
                        $input = $suggested_input;
                    }
                }
                else {
                    my ($e, $suggested_input) = _op_get($input);
                    if ($e == 0 && defined $suggested_input) {
                        $input = $suggested_input;
                    }
                }
            }
            if (defined $input) {
                print("\n$g_target:$g_mode> $input");
            }
            next;
        }
        elsif ($in eq 'A' && $last_char eq '[') {
            if (length($input) > 0) {
                print chr(8);    # . ' ' . chr(8);
                print ' ';
                print chr(8);    # . ' ' . chr(8);
                chop($input);
                $in = "";
            }
            if ($#history == -1) {
                next;
            }
            if (!defined $history[$history_index]) {
                next;
            }

            $in = '';
            for (my $count = 0 ; $count < length($input) ; $count++) {
                print chr(8);
                print ' ';
                print chr(8);    # . ' ' . chr(8);
            }
            if (defined $history[ $history_index - 1 ]) {
                $history_index--;
            }

            #           need to position cursor at beginning of line for print
            $input = $history[$history_index];
            print($input);
        }
        elsif ($in eq 'B' && $last_char eq '[') {
            if (length($input) > 0) {
                print chr(8);    # . ' ' . chr(8);
                print ' ';
                print chr(8);    # . ' ' . chr(8);
                chop($input);
                $in = "";
            }
            if ($#history == -1) {
                next;
            }
            if ($history_index == -1) {
                next;
            }
            if (!defined $history[$history_index]) {
                next;
            }

            $in = '';
            for (my $count = 0 ; $count < length($input) ; $count++) {
                print chr(8);
                print ' ';
                print chr(8);    # . ' ' . chr(8);
            }
            if (defined $history[ $history_index + 1 ]) {
                $history_index++;
            }

            #           need to position cursor at beginning of line for print
            $input = $history[$history_index];
            print($input);
        }
        elsif ($in eq 'C' && $last_char eq '[') {
            if (length($input) > 0) {
                print chr(8);    # . ' ' . chr(8);
                print ' ';
                print chr(8);    # . ' ' . chr(8);
                chop($input);
                $in = "";
            }
            $in = '';
        }
        elsif ($in eq 'D' && $last_char eq '[') {
            if (length($input) > 0) {
                print chr(8);    # . ' ' . chr(8);
                print ' ';
                print chr(8);    # . ' ' . chr(8);
                chop($input);
                $in = "";
            }
            $in = '';
        }
        elsif ($charkey == 3) {
            exit 0;
        }
        elsif ($charkey == 10) {
            last;
        }
        elsif ($charkey == 127 || $charkey == 8) {
            if (length($input) > 0) {
                print chr(8);    # . ' ' . chr(8);
                print ' ';
                print chr(8);    # . ' ' . chr(8);
                chop($input);
                $in = "";
            }
            else {
                next;
            }
        }
        elsif ($charkey < 32) {
            next;
        }
        else {
            $last_char = $in;
            $input .= $in;
        }
        printf($in);
    }

    #configure mode
    if (defined $input) {
        $history_index = -1;
        push(@history, $input);
        my $err_str;
        my $err = 0;
        if ($input =~ /^rest/) {

            #use this to assign the server
            my (undef, $local_op, $target, $arg4) = split(" ", $input);
            if (!defined $local_op) {
                next;
            }
            if ($local_op =~ /server/) {
                if (!defined $target || $target eq '') {
                    $g_target = "127.0.0.1";
                }
                else {
                    $g_target = $target;
                }
            }
            elsif ($local_op =~ /^proc/) {
                if (defined $target && $target =~ /delete/) {
                    if ($g_mode eq 'conf') {
                        ($err, undef) = _config_delete($arg4);
                    }
                    else {
                        ($err, undef) = _op_delete($arg4);
                    }
                }
                elsif (defined $target && $target =~ /use/) {
                    if ($g_mode eq 'conf') {
                        $g_conf_id = $arg4;
                    }
                    else {
                        $err     = 1;
                        $err_str = "ERROR: Only valid for conf mode";
                    }
                }
                elsif (!defined $target) {
                    if ($g_mode eq 'conf') {
                        ($err, undef) = _config_get();
                    }
                    else {
                        ($err, undef) = _op_get();
                    }
                }
            }
            elsif ($local_op =~ /^debug/) {
                $g_debug = 1;
            }
            elsif ($local_op =~ /^nodebug/) {
                $g_debug = 0;
            }
            elsif ($local_op =~ /^history/) {
                printf("\n");
                foreach my $v (@history) {
                    printf("$v\n");
                }
            }
            elsif ($local_op =~ /^user/) {
                if (defined $target) {

                    #assuming this to be 'username:password' format
                    $base64_string  = $target;
                    $g_encoded_auth = encode_base64($base64_string);
                    chop($g_encoded_auth);
                }
            }
            elsif ($local_op =~ /^show/) {
                _show_rest();
            }
        }
        elsif ($input =~ /configure/) {
            $err = _config_post($input);
            if ($err == 0) {
                $g_mode = 'conf';
            }
        }
        else {
            if ($g_mode eq 'conf') {
                if ($input =~ /^set/) {
                    $err = _config_put($input);
                }
                elsif ($input =~ /^delete/) {
                    $err = _config_put($input);
                }
                elsif ($input =~ /^comment/) {
                    $err = _config_put($input);
                }
                elsif ($input =~ /^activate/) {
                    $err = _config_put($input);
                }
                elsif ($input =~ /^deactivate/) {
                    $err = _config_put($input);
                }
                elsif ($input =~ /^show-all/) {
                    $err = _config_post($input);
                }
                elsif ($input =~ /^show/) {
                    $err = _config_post($input);
                }
                elsif ($input =~ /^commit/) {
                    $err = _config_post($input);
                }
                elsif ($input =~ /^save/) {
                    $err = _config_post($input);
                }
                elsif ($input =~ /^load/) {
                    $err = _config_post($input);
                }
                elsif ($input =~ /^merge/) {
                    $err = _config_post($input);
                }
                elsif ($input =~ /^exit/) {
                    if ($input =~ /^exit discard/) {
                        $err = _config_delete($g_conf_id);
                    }
                    $g_mode = 'op';
                }
                else {
                    print "unrecognized command: $input\n";
                }
            }
            elsif ($g_mode eq 'op') {
                $err = _op_post($input);
            }
        }
        if ($err == 0) {
            printf("\nOK");
        }
        else {
            printf("\nERROR");
            if (defined $err_str && $err_str ne '') {
                printf(": $err_str");
            }
        }
    }
    print("\n$g_target:$g_mode> ");
}
exit 0;

