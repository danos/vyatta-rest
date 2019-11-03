# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package App::Param::NonParam;

use strict;
use warnings;
use JSON;

use App::Param::Base;
our @ISA = qw(App::Param::Base);

sub new {
  my ($class, $href) = @_;
  my $self = $class->SUPER::new(undef, $href);
  # don't need value for NonParam unless it is user-defined
  if (!defined($href) or !defined($href->{value})) {
    delete($self->{DATA}->{value});
  }
  $self->{DATA}->{param} = JSON::false;
  bless($self, $class);
  return $self;
}

sub validate_value {
  my ($self, $val) = @_;
  return 1;
}

1;

