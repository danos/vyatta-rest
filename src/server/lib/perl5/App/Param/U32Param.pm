# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package App::Param::U32Param;

use strict;
use warnings;

use JSON;

use App::Param::Base;
our @ISA = qw(App::Param::Base);

use constant {U32_MAX => 2 ** 32};

sub new {
  my ($class, $value, $href) = @_;
  my $self = $class->SUPER::new($value, $href);
  $self->{DATA}->{param} = JSON::true;
  $self->{DATA}->{type} = 'u32';
  bless($self, $class);
  return $self;
}

sub validate_value {
  my ($self, $val) = @_;
  if (!($val =~ /^\d+$/)) {
    $self->{ERROR} = "\"$val\" is not a valid u32 value";
    return 0;
  }
  if ($val >= U32_MAX or $val < 0) {
    $self->{ERROR} = "\"$val\" is out of range for u32";
    return 0;
  }
  return 1;
}

1;

