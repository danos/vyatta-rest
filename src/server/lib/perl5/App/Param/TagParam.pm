# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package App::Param::TagParam;

use strict;
use warnings;
use JSON;

use App::Param::Base;
our @ISA = qw(App::Param::Base);

use Vyatta::Config;
use App::Param::Util;

my %valid_types = (
  'txt' => 1,
  'u32' => 1,
  'ipv4' => 1,
  'ipv4net' => 1,
  'ipv6' => 1,
  'ipv6net' => 1,
  'macaddr' => 1,
  'bool' => 1
);

sub new {
  my ($class, $type, $href) = @_;
  die 'Invalid type for tag node' if (!defined($type)
                                      or (!defined($valid_types{$type})));
  my $self = $class->SUPER::new(undef, $href);
  die 'Cannot set "value" or "values" for TagParam'
    if (defined($href) and (defined($href->{value})
                            or defined($href->{values})));
  # delete "value" set by base class constructor
  delete($self->{DATA}->{value});
  $self->{TAGS} = [];
  $self->{DATA}->{param} = JSON::true;
  $self->{DATA}->{type} = $type;
  my $type2 = $href->{type2};
  if (defined($type2)) {
    die 'Invalid type for tag node' if (!defined($valid_types{$type2}));
    $self->{DATA}->{type2} = $type2;
  }
  $self->{DATA}->{tagnode} = JSON::true;
  bless($self, $class);
  return $self;
}

sub validate_value {
  my ($self, $val) = @_;
  return 1;
}

sub addRawTag {
  my ($self, $tag) = @_;
  $tag->setParent($self);
  push @{$self->{TAGS}}, $tag;
}

sub addTag {
  my ($self, $tval, $href) = @_;
  if (!defined($href)) {
    $href = {tag=>JSON::true, rel_path=>''};
  } else {
    $href->{tag} = JSON::true;
    $href->{rel_path} = '';
  }
  my ($type1, $type2) = ($self->{DATA}->{type}, $self->{DATA}->{type2});
  my $tag;
  if (!defined($type2)) {
    $tag = App::Param::Util::createTypedParam($type1, $tval, $href);
  } else {
    $href->{type} = $type1;
    $href->{type2} = $type2;
    $tag = App::Param::Util::createMultiTypedParam($tval, $href);
  }
  $self->addRawTag($tag);
  return $tag;
}

sub addTagsFromRunningCfg {
  my $self = shift;
  my $path = $self->getMappedPath();
  my $running = new Vyatta::Config;
  my @tags = $running->listOrigNodes($path);
  for my $tag (@tags) {
    $self->addTag($tag);
  }
  if (scalar(@tags) == 0) {
    # no existing tags => set a dummy to allow traversal to continue
    $self->addTag($self->{TAG_DUMMY});
  }
}

sub addTagFromRunningCfg {
  # this adds a single tag from the running config
  my ($self, $tval) = @_;
  my $path = $self->getMappedPath();
  my $running = new Vyatta::Config;
  return if (!$running->existsOrig("$path $tval"));
  return $self->addTag($tval);
}

sub getTag {
  my ($self, $tval) = @_;
  for my $t (@{$self->{TAGS}}) {
    my $val = $t->getValue();
    return $t if ("$tval" eq "$val");
  }
  return undef;
}

sub getTags {
  my $self = shift;
  return @{$self->{TAGS}};
}

sub addChild {
  die 'Cannot call addChild() on a tag node';
}

sub getChild {
  die 'Cannot call getChild() on a tag node';
}

sub addParamFromRunningCfg {
  die 'Cannot call addParamFromRunningCfg() on a tag node';
}

sub getValue {
  die 'Cannot call getValue() on a tag node';
}

sub getValues {
  die 'Cannot call getValues () on a tag node';
}

sub getChildrenHash {
  die 'Cannot call getChildrenHash() on a tag node';
}

sub getDataTree {
  my $self = shift;
  my @tarr = ();
  for my $tag (@{$self->{TAGS}}) {
    push @tarr, $tag->getDataTree();
  }
  $self->{DATA}->{tags} = \@tarr;
  return $self->{DATA};
}

1;

