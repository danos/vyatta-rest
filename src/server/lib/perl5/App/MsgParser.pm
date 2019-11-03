# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package App::MsgParser;

use strict;
use warnings;

use JSON;

use Vyatta::Config;
use App::Param::Util;
use App::Param::NonParam;
use App::Param::TxtParam;
use App::Param::U32Param;
use App::Param::Ipv4Param;
use App::Param::Ipv4netParam;
use App::Param::Ipv6Param;
use App::Param::Ipv6netParam;
use App::Param::MacaddrParam;
use App::Param::BoolParam;
use App::Param::TagParam;
use App::Param::TypelessParam;
use App::Param::MultiTypeParam;

use constant {MAX_MSG_LEN => 512 * 1024};

sub _fromJsonInput {
  my $in_str = '';
  while (my $line = <STDIN>) {
    $in_str .= $line;
    die 'Input message too long' if (length($in_str) > MAX_MSG_LEN);
  }
  my $mref = undef;
  eval { $mref = from_json($in_str); };
  if ($@) {
    # "exception"
    die 'Invalid input message';
  }
  return $mref;
}

sub _recursiveParse {
  my $href = shift;
  
  # if not a Param/NonParam, just return it.
  return $href if (!defined($href->{param}));

  # just return it if invalid "param" value
  return $href if (!JSON::is_bool($href->{param}));

  if ($href->{param} and !defined($href->{type})) {
    # invalid (no type). just return it.
    return $href;
  }

  my %cparams = ();
  if (defined($href->{children})) {
    my ($n, $p);
    while (($n, $p) = each(%{$href->{children}})) {
      $cparams{$n} = _recursiveParse($p);
    }
  }

  my %data_hash = ();
  my ($k, $v);
  while (($k, $v) = each(%{$href})) {
    next if ($k eq 'children' or $k eq 'tags');
    $data_hash{$k} = $v;
  }

  my $param = undef;
  if (!$href->{param}) {
    # NonParam
    $param = new App::Param::NonParam(undef, \%data_hash);
  } elsif ($href->{tagnode}) {
    # TagParam
    $param = new App::Param::TagParam($href->{type}, \%data_hash);
    if (defined($href->{tags})) {
      # add the tags
      for my $t (@{$href->{tags}}) {
        $param->addRawTag(_recursiveParse($t));
      }
    }
  } elsif (defined($href->{type2})) {
    $param = new App::Param::MultiTypeParam(undef, \%data_hash);
  } elsif ($href->{type} eq 'txt') {
    $param = new App::Param::TxtParam(undef, \%data_hash);
  } elsif ($href->{type} eq 'u32') {
    $param = new App::Param::U32Param(undef, \%data_hash);
  } elsif ($href->{type} eq 'ipv4') {
    $param = new App::Param::Ipv4Param(undef, \%data_hash);
  } elsif ($href->{type} eq 'ipv4net') {
    $param = new App::Param::Ipv4netParam(undef, \%data_hash);
  } elsif ($href->{type} eq 'ipv6') {
    $param = new App::Param::Ipv6Param(undef, \%data_hash);
  } elsif ($href->{type} eq 'ipv6net') {
    $param = new App::Param::Ipv6netParam(undef, \%data_hash);
  } elsif ($href->{type} eq 'macaddr') {
    $param = new App::Param::MacaddrParam(undef, \%data_hash);
  } elsif ($href->{type} eq 'bool') {
    $param = new App::Param::BoolParam(undef, \%data_hash);
  } elsif ($href->{type} eq '') {
    $param = new App::Param::TypelessParam(\%data_hash);
  } else {
    # invalid type. just return it.
    return $href;
  }
  
  while (($k, $v) = each(%cparams)) {
    $param->addChild($k, $v);
  }
  return $param;
}

sub fromInput {
  # convert json string to perl objs
  my $mref = _fromJsonInput();
  # convert perl objs to param objs
  my %hash = ();
  my ($k, $v);
  while (($k, $v) = each(%{$mref})) {
    $hash{$k} = _recursiveParse($v);
  }
  return \%hash;
}

sub _recursiveWalk {
  my $href = shift;
  my @params = ($href);
  
  # if not a Param/NonParam, just return it.
  return @params if (App::Param::Util::isCustomObj($href));

  # if this param's "status" is "deleted", don't traverse subtree.
  return @params if ($href->isStatusDeleted());

  if ($href->isTagNode()) {
    # tag node. iterate tags.
    for my $tag ($href->getTags()) {
      push @params, _recursiveWalk($tag);
    }
  } else {
    # not tag node. iterate children.
    my ($n, $p);
    while (($n, $p) = each(%{$href->getChildrenHash()})) {
      $p->setName($n);
      push @params, _recursiveWalk($p);
    }
  }

  return @params;
}

sub iterateParams {
  my $root = shift;
  my @params = ();
  my ($n, $p);
  while (($n, $p) = each(%{$root})) {
    # skip if not a Param/NonParam
    next if (App::Param::Util::isCustomObj($p));
    $p->setName($n);
    push @params, _recursiveWalk($p);
  }
  return \@params;
}

1;

