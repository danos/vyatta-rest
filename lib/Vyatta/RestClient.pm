#!/usr/bin/perl
#
# Module: Vyatta::RestClient.pm
# Description: Module to simplified use of vyatta rest api.
# 
# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2017 by Brocade Communications Systems, Inc.
# All rights reserved.
# Copyright (c) 2009-2010 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package RestClient;

use strict;
use warnings;

use POSIX;
use JSON;
use MIME::Base64;
use Data::Dumper;
use IO::Socket::SSL qw(SSL_VERIFY_NONE);
use LWP::UserAgent;
use LWP::ConnCache;
use HTTP::Request;
use URI::Escape;
use IO::Pipe;

my %fields = (
    _target      => undef,
    _auth        => undef,
    _ua          => undef,
    _conf_loc    => undef,
    _debug       => undef,
    _uncommitted => undef,
);

sub new {
  my $that = shift;
  my $class = ref ($that) || $that;
  my $self = {
    %fields,
  };

  $self->{_ua} = LWP::UserAgent->new(
    ssl_opts => {
      verify_hostname => 0,
      SSL_verify_mode => SSL_VERIFY_NONE
    }
  );
  bless $self, $class;
  return $self;
}

sub debug {
    my ($self, $val) = @_;
    $self->{_debug} = $val;
    return;
}

sub timeout {
    my ($self, $val) = @_;
    my $ua = $self->{_ua};
    return $ua->timeout($val);
}

# Return the Vyatta spec version
sub get_vyatta_spec {
    my ($self, $resp) = @_;
    my $spec = $resp->header("Vyatta-Specification-Version");
    return $spec;
}

sub test_connectivity {
    my ($self, $target, $timeout) = @_;
    my $debug = $self->{_debug};

    my $finished = 0;
    
    if (!defined $timeout) {
        $timeout = 2; # default to 2 seconds
    }

    $SIG{CHLD} = sub { wait, $finished = 1 };
    
    my $pipe = new IO::Pipe();
    my $pid = fork;
    
    if($pid == 0) {
	$pipe->writer;
	my $response = $self->test_connectivity_internal($target,$timeout,$pipe);
	$pipe->print($response);
	exit;
    }
    
    $pipe->reader;
    
    sleep($timeout);
    
    if($finished) {
	print "test_connectivity: Finished!\n" if $debug;
	my @resp = $pipe->getlines;
	if (int($resp[0] / 100) != 5) {
	    return;
	}
	#return response on a server error--all else treated as successful connection
	return($resp[0],$resp[1]);
    }   
    else {
	print "test_connectivity: Killed!\n" if $debug;
	kill(9, $pid);
	#not truely a 500 condition as we are unable to connect
	return("500","Remote client is not reachable");
    }
    return;
}

sub test_connectivity_internal {
    my ($self, $target, $timeout, $pipe) = @_;

    my $ua    = $self->{_ua};
    my $debug = $self->{_debug};

    $ua->timeout($timeout);
    $ua->default_header('content-length' => 0);

    my $url = "https://$target/rest/conf";
    print "GET [$url]\n" if $debug;
    my $res = $ua->get($url);
    print $pipe $res->code . "\n";
    print $pipe $res->status_line . "\n";
    return;
}

sub auth_base64 {
    my ($self, $target, $auth) = @_;
    my $code;
    my $status_line;

    $self->{_target} = $target;
    $self->{_auth} = $auth;

    my $ua = $self->{_ua};

    $ua->default_header('content-length' => 0);
    $ua->default_header("authorization" => "Basic $auth");

    my $url = "https://$target/rest/conf";
    my $res = $ua->get($url);
    if ($res->is_error) {
        $code = $res->code;
        $status_line = $res->status_line;
        return ($code, $status_line);
    }

    # Verify valid Vyatta response
    my $spec = $self->get_vyatta_spec($res);
    if (!$spec) {
        $code = 401;
        $status_line = "Unauthorized";
        return ($code, $status_line);
    }
    return;
}

sub auth {
    my ($self, $target, $user, $passwd) = @_;
    
    my $auth = encode_base64("$user:$passwd");
    return auth_base64($self, $target, $auth);
}

sub _send_delete {
    my ($ua, $url) = @_;

    my $request = HTTP::Request->new(DELETE => $url);
    my $response = $ua->request($request);
    return if $response->is_success;
    return "Error delete [$url] - $response->status_line";
}

sub _cmd_2_path {
    my ($cmd) = @_;

    my ($path, $leaf);
    if ($cmd =~ /^(.*)('.*')$/) {
        $path = $1;
        $leaf = $2;
    } elsif ($cmd =~ /^(.*)(".*")$/) {
        $path = $1;
        $leaf = $2;
    }else {
        $path = $cmd;
        $leaf = undef;
    }

    my @tokens = split(' ', $path);
    push @tokens, $leaf if defined $leaf;

    my @etokens = ();
    foreach my $token (@tokens) {
        $token = uri_escape($token);
        $token =~ s/\'/%27/g;
        push @etokens, $token;
    }

    $path = join('/', @etokens);
    return $path;
}

sub _read_op_output {
    my ($ua, $target, $location, $limit, $debug) = @_;
    
    my $url = "https://$target/$location";
    my ($response, $output, $chunk, $count, $err);


    $count  = 0;
    $output = ();
    $err    = undef;
    do {
        print "GET [$url]\n"  if $debug;
        $response = $ua->get($url);
        if ($debug) {
            print $response->status_line, "\n";
            print $response->content;
        }
        if ($response->is_success) {
            $chunk = $response->content;
            $chunk =~ s/[\x00-\x08\x0B-\x1F\x7F-\xFF]//g; # strip unprintable
            if ($chunk eq '') {
                if ($count++ > 10) {
                    $output .= "\nNo new output - Stopping\n";
                    $err = _send_delete($ua, $url);
                }
            }
            if ($limit) {
                if (--$limit == 0) {
                    $output .= "\nLimit exceeded - Stopping\n";
                    $err = _send_delete($ua, $url);
                    return;
                }
            }
            $output .= $chunk;
        } else {
            if ($response->code != 410) {
                my $err = "Failed to GET [$url] - " . $response->status_line;
                return ($err, undef);
            }
        }
    } while ($response->code != 410);
    
    return ($err, $output);
}

sub _is_op_cmd_valid {
    my ($self, $path) = @_;

    my $target = $self->{_target};
    my $ua     = $self->{_ua};
    my $url    = "https://$target/rest/op/$path/";

    my $response = $ua->get($url);
    return 1 if $response->is_success;
    return 0;
}

sub _find_op_last_valid {
    my ($self, $path) = @_;

    my $target = $self->{_target};
    my $ua     = $self->{_ua};
    my $url    = "https://$target/rest/op/$path/";

    my $tmp_path;
    my $i = 0;
    while ($i = index("$path/", '/', $i)) {
        last if $i < 0;
        $tmp_path = substr("$path/", 0, $i+1);
        if (! _is_op_cmd_valid($self, $tmp_path)) {
            chop $tmp_path;
            my $j = rindex($tmp_path, '/');
            return substr($tmp_path, $j+1);
        }
        $i++;
    }
    return;
}

#
# Run a simple app-mode command.
#
sub run_app_cmd {
    my ($self, $cmd, $arg) = @_;

    my $target = $self->{_target};
    my $ua     = $self->{_ua};
    my $path   = _cmd_2_path($cmd);
    my $url    = "https://$target/rest/app/$path";
    my $debug  = $self->{_debug};
    my $response;

    print "POST [$url]\n" if $debug;
    if (defined($arg)) {
	$response = $ua->post($url, 'Content-Type' => "application/json", 'Content' => $arg);
    } else {
	$response = $ua->post($url, 'Content-Type' => "application/json");
    }

    my ($err, $output);
    if ($response->is_success) {
	return (undef, $response->content);
    } else {
        my $err = "run_app_cmd POST failed [$url] - " . $response->status_line; 
        return ($err, undef);
    }
}

sub run_app_get_cmd {
    my ($self, $cmd, $arg) = @_;

    my $target = $self->{_target};
    my $ua     = $self->{_ua};
    my $path   = _cmd_2_path($cmd);
    my $url    = "https://$target/rest/app/$path";
    my $debug  = $self->{_debug};
    my $response;

    print "GET [$url]\n" if $debug;
	  $response = $ua->get($url);

    my ($err, $output);
    if ($response->is_success) {
	      return (undef, $response->content);
    } else {
        my $err = "run_app_cmd GET failed [$url] - " . $response->status_line; 
        return ($err, undef);
    }
}

sub run_op_cmd {
    my ($self, $cmd, $limit) = @_;
    
    my $target = $self->{_target};
    my $ua     = $self->{_ua};
    my $path   = _cmd_2_path($cmd);
    my $url    = "https://$target/rest/op/$path";
    my $debug  = $self->{_debug};

    if (! _is_op_cmd_valid($self, $path)) {
        my $last = _find_op_last_valid($self, $path);
        return ("Invalid cmd [$cmd] at [$last]", undef);
    }

    print "POST [$url]\n" if $debug;
    my $response = $ua->post($url);
    if ($debug) {
        print $response->status_line, "\n";
        print $response->content;
    }

    $limit = 0 if ! defined $limit;
    $limit = 20 if $path =~ /capture$/;

    my ($err, $output);
    if ($response->is_success) {
        my $location = $response->header('Location');
        if (defined $location) {
            ($err, $output) = _read_op_output($ua, $target, $location, 
                                              $limit, $debug);
            return ($err, $output);
        } else {
            my $err = "run_op_cmd: no location found [$url] - " 
                    . $response->status_line;
            return ($err, undef);
        }
    } else {
        my $err = "run_op_cmd GET failed [$url] - " . $response->status_line; 
        return ($err, undef);
    }
}

sub conn_cache {
    my ($self, $value) = @_;

    my $ua = $self->{_ua};
    if ($value) {
        $ua->conn_cache(LWP::ConnCache->new());
        # $LWP::ConnCache::DEBUG = 1;
    } else {
        $ua->conn_cache => undef;
    }
    
}

sub configure {
    my ($self) = @_;

    my $target = $self->{_target};
    my $ua     = $self->{_ua};
    my $url    = "https://$target/rest/conf";
    
    my $location = $self->{_conf_loc};
    _send_delete($ua, "$url/$location") if defined $location;

    my $response = $ua->post($url);
    if ($response->is_error) {
        my $err = "configure failed [$url] - " . $response->status_line;
        $self->{_conf_loc} = undef;
        return ($err, undef);
    }
    $location = $response->header('Location');
    $self->{_conf_loc} = $location;
    $self->{_uncommitted} = 0;
    return;
}

sub configure_show {
    my ($self, $cmd) = @_;

    my $target   = $self->{_target};
    my $ua       = $self->{_ua};
    my $location = $self->{_conf_loc};
    my $path     = _cmd_2_path($cmd);

    if (! defined $location) {
        return "configure_show called without session [$cmd]" 
    }

    my $url      = "https://$target/$location/$path";
    my $request  = HTTP::Request->new(GET => "$url");
    my $response = $ua->request($request);
    my @nodes = ();
    print "configure_show [$url]\n", $response->content, "\n" if $self->{_debug};
    if ($response->is_error) {
        my $err = "Error: configure_show [$cmd]\n";
        return ($err);
    }


    if ($response->header('content-type') eq 'application/json') {
        my $perl_scalar;
        eval {
            $perl_scalar = decode_json($response->content);
        };
        if ($@) {
            warn $@ if $self->{_debug};
        } else {
            my $children = $perl_scalar->{children};
            if (defined $children) {
                my $i = 0;
                do {
                    if (defined $children->[$i]->{name}) {
                        push @nodes, $children->[$i]->{name};
                    }
                    $i++;
                } while ($children->[$i]);
            }
        }
    }
    return (undef, @nodes);
}

sub _get_error_message {
    my ($self, $response) = @_;

    return if $response->header('content-type') ne 'application/json';

    my $perl_scalar;
    eval {
        $perl_scalar = decode_json($response->content);
    };
    if ($@) {
        print "JSON decode error\n";
        warn $@ if $self->{_debug};
    } else {
        my $message = $perl_scalar->{message};
        return $message if defined $message and $message ne ' ';
    }
    return;
}

sub set {
    my ($self, $cmd) = @_;

    my $target   = $self->{_target};
    my $ua       = $self->{_ua};
    my $location = $self->{_conf_loc};
    my $path     = _cmd_2_path($cmd);

    if (! defined $location) {
        return "set called without session [$cmd]" 
    }

    my $url      = "https://$target/$location/$path";
    my $request  = HTTP::Request->new(PUT => "$url");
    my $response = $ua->request($request);
    print "set url [$url]\n", $response->content, "\n" if $self->{_debug};
    if ($response->is_error) {
        my $message = _get_error_message($self, $response);
        return $message if defined $message;
        return "set error on put [$url] - " . $response->status_line;
    }
    $self->{_uncommitted}++;
    return;
}

sub delete {
    my ($self, $cmd) = @_;
    return set($self, $cmd);
}

sub uncommitted {
    my ($self) = @_;

    return $self->{_uncommitted};
}

sub commit {
    my ($self) = @_;

    my $target   = $self->{_target};
    my $ua       = $self->{_ua};
    my $location = $self->{_conf_loc};
    my $debug    = $self->{_debug};

    print "Committing ", $self->{_uncommitted}, " cmds\n" if $debug;
    if (! defined $location) {
        return "commit called without session" 
    }    

    my $start    = time;
    my $url      = "https://$target/$location/commit";
    my $response = $ua->post($url);
    my $end      = time;
    my $message  = _get_error_message($self, $response);
    print(($end - $start), " - message [$message]\n") if $message and $debug;
    if ($response->is_error) {
        return $message if defined $message;
        return "commit post failed [$url] - ", $response->status_line;
    }
    $self->{_uncommitted} = 0;
    return "$message\n" if defined $message;
    return;
}

sub save {
    my ($self) = @_;

    my $target   = $self->{_target};
    my $ua       = $self->{_ua};
    my $location = $self->{_conf_loc};
    
    if (! defined $location) {
        return "save called without session" 
    }    

    my $url      = "https://$target/$location/save";
    my $response = $ua->post($url);
    if ($response->is_error) {
        my $message = _get_error_message($self, $response);
        return $message if defined $message;
        return "save post failed [$url] - " . $response->status_line;
    }
    return;
}

sub configure_exit {
    my ($self) = @_;

    my $target   = $self->{_target};
    my $ua       = $self->{_ua};
    my $location = $self->{_conf_loc};

    if (! defined $location) {
        return "configure_exit called without session" 
    }    
    if ($self->{_uncommitted} > 0) {
        return "uncommitted changes";
    }

    my $url = "https://$target/$location";
    $self->{_conf_loc} = undef;
    $self->{_uncommitted} = undef;
    my $request  = HTTP::Request->new(DELETE => $url);
    my $response = $ua->request($request);
    if ($response->is_error) {
        my $message = _get_error_message($self, $response);
        return $message if defined $message;
        return "configure_exit delete failed [$url] - " . $response->status_line;
    }
    return;
}

sub configure_exit_discard {
    my ($self) = @_;

    my $location = $self->{_conf_loc};
    if (! defined $location) {
        return "configure_exit called without session" 
    }    
    $self->{_uncommitted} = 0;
    return configure_exit($self);
}

sub batch_conf_cmds {
    my ($self, @cmds) = @_;

    my $target = $self->{_target};
    my $ua     = $self->{_ua};
    my $err;

    $err = configure($self);
    return "configure error: $err" if defined $err;

    foreach my $cmd (@cmds) {
        $err = set($self, $cmd);
        return "set error: $err" if defined $err;
    }

    $err = commit($self);
    return "commit error: $err" if defined $err;

    $err = save($self);
    return "save error: $err" if defined $err;

    $err = configure_exit($self);
    return "configure_exit error: $err" if defined $err;
    return;
}

1;
