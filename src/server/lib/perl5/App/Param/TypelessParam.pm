# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package App::Param::TypelessParam;

use strict;
use warnings;
use JSON;

use App::Param::Base;
our @ISA = qw(App::Param::Base);

sub new {
  my ($class, $href) = @_;
  my $self = $class->SUPER::new(undef, $href);
  die 'Cannot set "value" or "values" for typeless node'
    if (defined($href) and (defined($href->{value})
                            or defined($href->{values})));
  # delete "value" set by base class constructor
  delete($self->{DATA}->{value});
  $self->{DATA}->{param} = JSON::true;
  $self->{DATA}->{type} = '';
  bless($self, $class);
  return $self;
}

sub validate_value {
  my ($self, $val) = @_;
  return 1;
}

1;

