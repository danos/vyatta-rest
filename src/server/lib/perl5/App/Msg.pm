# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package App::Msg;

use strict;
use warnings;

use JSON;

use Vyatta::Config;
use App::Param::Util;

sub new {
  my ($class, $href) = @_;
  my $self = {};
  $self->{CHILDREN} = {};
  $self->{DATA} = {};
  if (defined($href)) {
    my ($k, $v);
    while (($k, $v) = each(%{$href})) {
      $self->{DATA}->{$k} = $v;
    }
  }
  bless($self, $class);
  return $self;
}

sub addChild {
  my ($self, $param_name, $param_ref) = @_;
  $self->{CHILDREN}->{$param_name} = $param_ref;
}

sub addHashedParamsFromRunningCfg {
  my ($self, $href) = @_;
  my ($pname, $data);
  while (($pname, $data) = each(%{$href})) {
    my ($ppath, $phref) = (undef, undef);
    if (ref($data) eq '') {
      $ppath = $data;
    } elsif (ref($data) eq 'ARRAY') {
      ($ppath, $phref) = @{$data};
    } else {
      die 'Hashed param data must be "scalar" or "array ref"';
    }
    $self->addParamFromRunningCfg($pname, $ppath, $phref);
  }
}

sub addParamFromRunningCfg {
  my ($self, $pname, $ppath, $href) = @_;
  die "Must provide param's name and path"
    if (!defined($pname) or !defined($ppath));

  my $pa = App::Param::Util::createParamFromRunningCfg($ppath, $href);
  die "\"$ppath\" is a tag node" if ($pa->isTagNode());
  $self->addChild($pname, $pa);
  return $pa;
}

sub addTagParamFromRunningCfg {
  my ($self, $tname, $tpath, $href) = @_;
  my $t = App::Param::Util::createParamFromRunningCfg($tpath, $href);
  die "\"$tpath\" is not a tag node" if (!$t->isTagNode());
  $self->addChild($tname, $t);
  return $t;
}

sub addTreeFromRunningCfg {
  my ($self, $root_path, $recur_depth_limit) = @_;
  if (!defined($recur_depth_limit)) {
    $recur_depth_limit = 0;
  }
  my @root_paths = ($root_path);
  if ($root_path =~ /^\s*$/) {
    # empty root => everything (including unset ones)
    my $running = new Vyatta::Config();
    @root_paths = $running->getTmplChildren('');
  }
  for my $rpath (@root_paths) {
    my $root = App::Param::Util::createParamFromRunningCfg($rpath);
    if (!defined($root)) {
      # not a valid param. maybe it's a "tag value"?
      # try going up one level and see if it's a "tag node".
      my $tpath = $rpath;
      $tpath =~ s/\s+(\S+)$//;
      my $tval = $1;
      $root = App::Param::Util::createParamFromRunningCfg($tpath);
      if (!defined($root) or !$root->isTagNode()) {
        # either the path is invalid or the path is not a tag node
        die "Invalid config path \"$rpath\"";
      }
      my $troot = $root->addTagFromRunningCfg($tval);
      die "Invalid config path \"$rpath\"" if (!defined($troot));
      $troot->addSubtreeFromRunningCfg(1, $recur_depth_limit);
    } else {
      $root->addSubtreeFromRunningCfg(1, $recur_depth_limit);
    }
    $rpath =~ s/\s/_/g;
    $self->addChild($rpath, $root);
  }
}

sub getDataTree {
  my $self = shift;
  my ($ck, $cv);
  while(($ck, $cv) = each(%{$self->{CHILDREN}})) {
    if (App::Param::Util::isCustomObj($cv)) {
      # not a Param/NonParam
      $self->{DATA}->{$ck} = $cv;
    } else {
      $self->{DATA}->{$ck} = $cv->getDataTree();
    }
  }
  return $self->{DATA};
}

sub getChild {
  my ($self, $pname) = @_;
  return $self->{CHILDREN}->{$pname};
}

sub _recursiveWalk {
  my $href = shift;
  my @params = ($href);

  # if not a Param/NonParam, just return it.
  return @params if (App::Param::Util::isCustomObj($href));

  if ($href->isTagNode()) {
    # tag node. iterate tags.
    for my $tag ($href->getTags()) {
      push @params, _recursiveWalk($tag);
    }
  } else {
    # not tag node. iterate children.
    my ($n, $p);
    while (($n, $p) = each(%{$href->getChildrenHash()})) {
      push @params, _recursiveWalk($p);
    }
  }

  return @params;
}

sub iterateParams {
  my $self = shift;
  my @params = ();
  my ($n, $p);
  while (($n, $p) = each(%{$self->{CHILDREN}})) {
    # skip if not a Param/NonParam
    next if (App::Param::Util::isCustomObj($p));
    push @params, _recursiveWalk($p);
  }
  return \@params;
}

sub serialize {
  my $self = shift;
  return to_json($self->getDataTree(), {pretty => 1});
}

sub setResponseStatus {
  my ($self, $status) = @_;
  $self->{RESP_STATUS} = $status;
}

sub _parseEnumOut {
  my $out = shift;
  my @array = ();
  if ($out =~ /\n/) {
    @array = split /\n/, $out;
  } else {
    @array = split /\s/, $out;
  }
  return \@array;
}

my $ENUM_SCRIPT_DIR = '/opt/vyatta/share/enumeration';
sub generateEnum {
  my $self = shift;
  my $params = $self->iterateParams();
  my %enums = ();
  for my $p (@{$params}) {
    if (defined($p->{DATA}->{enum})) {
      $enums{$p->{DATA}->{enum}} = 1;
    }
  }
  my %enumerations = ();
  for my $e (keys %enums) {
    my $script = "$ENUM_SCRIPT_DIR/$e";
    next if (! -f "$script" or ! -e "$script");
    my $out = `$script 2>/dev/null`;
    $enumerations{$e} = _parseEnumOut($out);
  }
  if (scalar(keys %enumerations) > 0) {
    $self->{DATA}->{enumerations} = \%enumerations;
  }
}

sub send {
  my $self = shift;
  # XXX need to communicate $self->{RESP_STATUS} to fcgi backend. currently
  # the backend only looks at exit status and always use 500 status for
  # non-zero exit status.
  # XXX the fcgi backend should also allow app handlers to return
  # "Content-Type" so that an app can return different types of data, e.g.,
  # a jpeg image, etc.

  # generate enumeration values
  $self->generateEnum();

  # only output if we have something.
  if (scalar(keys(%{$self->{CHILDREN}})) > 0
      or scalar(keys(%{$self->{DATA}})) > 0) {
    print $self->serialize();
  }
}

1;

