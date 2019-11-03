# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package App::Param::TxtParam;

use strict;
use warnings;
use JSON;

use App::Param::Base;
our @ISA = qw(App::Param::Base);

sub new {
  my ($class, $value, $href) = @_;
  my $self = $class->SUPER::new($value, $href);
  $self->{DATA}->{param} = JSON::true;
  $self->{DATA}->{type} = 'txt';
  bless($self, $class);
  return $self;
}

sub validate_value {
  my ($self, $val) = @_;
  return 1;
}

1;

