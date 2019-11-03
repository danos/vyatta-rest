# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package App::Param::MultiTypeParam;

use strict;
use warnings;
use JSON;

use Vyatta::TypeChecker;
use App::Param::Base;
our @ISA = qw(App::Param::Base);

sub new {
  my ($class, $value, $href) = @_;
  # $href has the two types
  my $self = $class->SUPER::new($value, $href);
  $self->{DATA}->{param} = JSON::true;
  bless($self, $class);
  return $self;
}

sub validate_value {
  my ($self, $val, $href) = @_;
  my ($t1, $t2) = ($self->{DATA}->{type}, $self->{DATA}->{type2});
  if (!validateType($t1, $val) and !validateType($t2, $val)) {
    $self->{ERROR} = "\"$val\" is not a valid \"$t1\" or \"$t2\" value";
    return 0;
  }
  return 1;
}

1;

