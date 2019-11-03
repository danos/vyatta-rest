# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package App::Param::MacaddrParam;

use strict;
use warnings;
use JSON;

use Vyatta::TypeChecker;
use App::Param::Base;
our @ISA = qw(App::Param::Base);

sub new {
  my ($class, $value, $href) = @_;
  my $self = $class->SUPER::new($value, $href);
  $self->{DATA}->{param} = JSON::true;
  $self->{DATA}->{type} = 'macaddr';
  bless($self, $class);
  return $self;
}

sub validate_value {
  my ($self, $val) = @_;
  if (!validateType('macaddr', $val)) {
    $self->{ERROR} = "\"$val\" is not a valid \"macaddr\" value";
    return 0;
  }
  return 1;
}

1;

