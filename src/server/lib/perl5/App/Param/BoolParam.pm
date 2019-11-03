# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package App::Param::BoolParam;

use strict;
use warnings;
use JSON;

use App::Param::Base;
our @ISA = qw(App::Param::Base);

sub str2bool {
  my $str = shift;
  return $str if (!defined($str) or JSON::is_bool($str));
  if ($str eq 'true') {
    return JSON::true;
  } elsif ($str eq 'false') {
    return JSON::false;
  }
  die "\"$str\" is not a valid bool value";
}

sub new {
  my ($class, $value, $href) = @_;
  die 'Bool param only takes scalar value' if (ref($value) ne '');
  $value = str2bool($value);
  if (defined($href) and defined($href->{default})) {
    $href->{default} = str2bool($href->{default});
  }
  my $self = $class->SUPER::new($value, $href);
  $self->{DATA}->{param} = JSON::true;
  $self->{DATA}->{type} = 'bool';
  bless($self, $class);
  return $self;
}

sub validate_value {
  my ($self, $val) = @_;
  if (!JSON::is_bool($val)) {
    $self->{ERROR} = "\"$val\" is not a valid bool value";
    return 0;
  }
  return 1;
}

1;

