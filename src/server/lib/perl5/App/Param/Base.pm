# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package App::Param::Base;

use strict;
use warnings;

use JSON;

use Vyatta::Config;
use App::Param::Util;

sub new {
  my ($class, $value, $href) = @_;
  my $self = {};
  $self->{CHILDREN} = {};
  $self->{DATA} = {};
  # this is for dummy tag node
  $self->{TAG_DUMMY} = '___NODE.TAG___';
  if (ref($value) eq '') {
    # single-value node
    $self->{DATA}->{value} = $value;
  } elsif (ref($value) eq 'ARRAY') {
    # multi-value node
    $self->{DATA}->{values} = $value;
  } else {
    # invalid value ref
    die 'Param value must be "scalar" or "array ref"';
  }
  if (defined($href)) {
    my ($k, $v);
    while (($k, $v) = each(%{$href})) {
      $self->{DATA}->{$k} = $v;
    }
  }
  bless($self, $class);
  die "Invalid value: $self->{ERROR}" if (!$self->validate());
  return $self;
}

sub addChild {
  my ($self, $param_name, $param_ref) = @_;
  $self->{CHILDREN}->{$param_name} = $param_ref;
  $param_ref->setParent($self);
}

sub getChild {
  my ($self, $cname) = @_;
  return $self->{CHILDREN}->{$cname};
}

sub setParent {
  my ($self, $parent_ref) = @_;
  $self->{PARENT} = $parent_ref;
}

sub getParent {
  my $self = shift;
  return $self->{PARENT};
}

sub _addParamFromRunningCfg {
  my ($self, $pname, $ppath, $href) = @_;
  my $pa = App::Param::Util::createParamFromRunningCfg($ppath, $href, $self);
  $self->addChild($pname, $pa);
  return $pa;
}

# this is only for non-tag nodes
sub addParamFromRunningCfg {
  my ($self, $pname, $ppath, $href) = @_;
  my $pa = $self->_addParamFromRunningCfg($pname, $ppath, $href);
  die "\"$ppath\" is a tag node" if ($pa->isTagNode());
  return $pa;
}

# this is only for tag nodes
sub addTagParamFromRunningCfg {
  my ($self, $tname, $tpath, $href) = @_;
  my $t = $self->_addParamFromRunningCfg($tname, $tpath, $href);
  die "\"$tpath\" is not a tag node" if (!$t->isTagNode());
  return $t;
}

sub addSubtreeFromRunningCfg {
  my ($self, $recur_depth, $recur_depth_limit) = @_;
  if (defined($recur_depth) and defined($recur_depth_limit)
      and ($recur_depth_limit > 0) and ($recur_depth > $recur_depth_limit)) {
    return;
  }
  if ($self->isTagNode()) {
    # tag node => add all tags
    $self->addTagsFromRunningCfg();
    for my $tag ($self->getTags()) {
      $tag->addSubtreeFromRunningCfg($recur_depth + 1, $recur_depth_limit);
    }
  } elsif ($self->isTypeless() or $self->isTagValue()) {
    # add all children if this is a:
    #   typeless, non-tag node
    #   or
    #   tag value
    my $running = new Vyatta::Config();
    for my $cname ($running->getTmplChildren($self->getMappedPath())) {
      my $pa = $self->_addParamFromRunningCfg($cname, $cname);
      $pa->addSubtreeFromRunningCfg($recur_depth + 1, $recur_depth_limit);
    }
  }
  # a typed, non-tag node is a leaf, so no subtree to add
}

sub validate {
  my $self = shift;
  my @vals = ();
  if ($self->isMulti()) {
    if (ref($self->{DATA}->{values}) ne 'ARRAY') {
      $self->{ERROR} = 'Multi-value node value is not array ref';
      return 0;
    }
    @vals = @{$self->{DATA}->{values}};
  } else {
    my $val = $self->{DATA}->{value};
    if (defined($val) and $val eq $self->{TAG_DUMMY}) {
      # ignore dummy entry
      return 1;
    }
    @vals = ($val);
  }
  foreach my $v (@vals) {
    next if (!defined($v));
    return 0 if (!$self->validate_value($v));
  }
  return 1;
}

sub isParam {
  my $self = shift;
  return 0 if (!defined($self->{DATA}->{param}));
  return 0 if (!JSON::is_bool($self->{DATA}->{param}));
  return $self->{DATA}->{param};
}

sub isMulti {
  my $self = shift;
  return 1 if (defined($self->{DATA}->{values}));
  return 0;
}

sub isTypeless {
  my $self = shift;
  return 0 if (!defined($self->{DATA}->{type}) or $self->{DATA}->{type} ne '');
  return 1;
}

sub isTagNode {
  my $self = shift;
  return $self->{DATA}->{tagnode};
}

sub isTagValue {
  my $self = shift;
  return $self->{DATA}->{tag};
}

sub isStatusDeleted {
  my $self = shift;
  my $status = $self->{DATA}->{status};
  return (defined($status) and $status eq 'deleted');
}

sub getValue {
  my $self = shift;
  die 'getValue() can only be called on a param' if (!$self->isParam());
  die 'getValue() cannot be called on a multi-value node'
    if ($self->isMulti());
  return $self->{DATA}->{value};
}

sub getValues {
  my $self = shift;
  die 'getValues() can only be called on a param' if (!$self->isParam());
  die 'getValues() can only be called on a multi-value node'
    if (!$self->isMulti());
  return $self->{DATA}->{values};
}

sub getChildrenHash {
  my $self = shift;
  return $self->{CHILDREN};
}

sub getDataTree {
  my $self = shift;
  my %carr = ();
  my ($ck, $cv);
  while(($ck, $cv) = each(%{$self->{CHILDREN}})) {
    $carr{$ck} = $cv->getDataTree();
  }
  if (scalar(keys(%carr)) > 0) {
    $self->{DATA}->{children} = \%carr;
  }
  return $self->{DATA};
}

sub isMapped {
  my $self = shift;
  return (defined($self->{DATA}->{cfg_path})
          or defined($self->{DATA}->{rel_path}));
}

sub getMappedPath {
  my $self = shift;
  my $rpath = $self->{DATA}->{rel_path};
  if ($self->isTagValue()) {
    # this is a tag. append value (the new one if it exists).
    my $val = $self->{DATA}->{value};
    my $nval = $self->{DATA}->{'new-value'};
    if (defined($nval)) {
      $val = $nval;
    }
    if (defined($rpath) and $rpath ne '') {
      $rpath .= " $val";
    } else {
      $rpath = "$val";
    }
  }
  return $self->{DATA}->{cfg_path} if (defined($self->{DATA}->{cfg_path}));
  die 'Cannot get absolute mapped path'
    if (!defined($rpath) or !defined($self->getParent()));
  return ($self->getParent()->getMappedPath() . ' ' . $rpath)
}

sub _getConfigSetCommands {
  # passing $path is optimization (avoid doing recursive getMappedPath again)
  my ($self, $path) = @_;
  my @cmds = ();
  return () if (!defined($path));
  if ($self->isMulti()) {
    my $nvals = $self->{DATA}->{'new-values'};
    return () if (!defined($nvals));
    push @cmds, "delete $path";
    for my $v (@{$nvals}) {
      push @cmds, "set $path '$v'";
    }
  } else {
    my $nval = $self->{DATA}->{'new-value'};
    return () if (!defined($nval));
    push @cmds, "set $path '$nval'";
  }
  return @cmds;
}

sub getConfigCommands {
  my $self = shift;
  return () if (!$self->isMapped() or !defined($self->{DATA}->{status}));
  my ($status, $path) = ($self->{DATA}->{status}, $self->getMappedPath());
  return ("delete $path") if ($status eq 'deleted');
  if ($self->isTypeless()) {
    # typeless node
    return ("set $path") if ($status eq 'added');
    return ();
  }
  if ($self->isTagValue()) {
    # a "tag"
    if ($status eq 'changed') {
      # "tag" is changed => rename
      my @parr = split / +/, $path;
      my $val = $self->{DATA}->{value};
      my $nval = $self->{DATA}->{'new-value'};
      return () if (!defined($val) or !defined($nval));
      pop @parr;
      my $cmd = join ' ', ('move', @parr, $val, 'to', $nval);
      return ($cmd);
    } elsif ($status eq 'added') {
      # new "tag". path already has the new value.
      return ("set $path");
    }
  }
  if ($status eq 'changed' or $status eq 'added') {
    return $self->_getConfigSetCommands($path);
  }
}

sub setName {
  my ($self, $name) = @_;
  # note: this is only set by MsgParser::iterateParams
  $self->{DATA}->{name} = $name;
}

sub getName {
  my $self = shift;
  # note: this is only set by MsgParser::iterateParams
  return $self->{DATA}->{name};
}

sub serialize {
  my $self = shift;
  return to_json($self->getDataTree(), {pretty => 1});
}

1;

