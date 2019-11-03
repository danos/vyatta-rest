# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package App::Param::Util;

use strict;
use warnings;

use Vyatta::Config;
use App::Param::TypelessParam;
use App::Param::TxtParam;
use App::Param::U32Param;
use App::Param::Ipv4Param;
use App::Param::Ipv4netParam;
use App::Param::Ipv6Param;
use App::Param::Ipv6netParam;
use App::Param::MacaddrParam;
use App::Param::BoolParam;
use App::Param::TagParam;
use App::Param::MultiTypeParam;

# static methods
sub createTypedParam {
  my ($type, $value, $href) = @_;
  my $param = undef;
  if (!defined($type)) {
    $param = new App::Param::TypelessParam($href);
  } elsif ($type eq 'txt') {
    $param = new App::Param::TxtParam($value, $href);
  } elsif ($type eq 'u32') {
    $param = new App::Param::U32Param($value, $href);
  } elsif ($type eq 'ipv4') {
    $param = new App::Param::Ipv4Param($value, $href);
  } elsif ($type eq 'ipv4net') {
    $param = new App::Param::Ipv4netParam($value, $href);
  } elsif ($type eq 'ipv6') {
    $param = new App::Param::Ipv6Param($value, $href);
  } elsif ($type eq 'ipv6net') {
    $param = new App::Param::Ipv6netParam($value, $href);
  } elsif ($type eq 'macaddr') {
    $param = new App::Param::MacaddrParam($value, $href);
  } elsif ($type eq 'bool') {
    $param = new App::Param::BoolParam($value, $href);
  } else {
    die "Type \"$type\" is not supported yet";
  }
  return $param;
}

sub createMultiTypedParam {
  my ($value, $href) = @_;
  my ($type, $type2) = ($href->{type}, $href->{type2});
  if (!defined($type) or !defined($type2)) {
    die 'Multi-typed param with undefined type(s)';
  }
  return (new App::Param::MultiTypeParam($value, $href));
}

sub createParamFromRunningCfg {
  my ($ppath, $href, $parent) = @_;
  my $real_path = $ppath;
  if (!defined($parent)) {
    # not hierarchical. use absolute path.
    if (!defined($href)) {
      $href = {cfg_path=>$ppath};
    } else {
      $href->{cfg_path} = $ppath;
    }
  } else {
    # use relative path
    die 'Cannot create param under unmapped param' if (!$parent->isMapped());
    my $parent_path = $parent->getMappedPath();
    $real_path = "$parent_path $ppath";
    if (!defined($href)) {
      $href = {rel_path=>$ppath};
    } else {
      $href->{rel_path} = $ppath;
    }
  }
  my $running = new Vyatta::Config();
  my $tmpl = $running->parseTmplAll($real_path);
  if (!defined($tmpl)) {
    # can't find template. not fatal so return.
    return;
  }

  if (defined($tmpl->{default})) {
    $href->{default} = $tmpl->{default};
  }
  if (defined($tmpl->{limit})) {
    $href->{max_vals} = $tmpl->{limit};
  }
  if (defined($tmpl->{type2})) {
    $href->{type2} = $tmpl->{type2};
  }
  if (defined($tmpl->{enum})) {
    $href->{enum} = $tmpl->{enum};
  }

  my $val = undef;
  if ($tmpl->{tag}) {
    # tag
    die 'tag node has no type' if (!defined($tmpl->{type}));
    return (new App::Param::TagParam($tmpl->{type}, $href));
  } elsif (!defined($tmpl->{type})) {
    # typeless node
    if ($running->existsOrig($real_path)) {
      $href->{exists} = JSON::true;
    } else {
      $href->{exists} = JSON::false;
    }
  } elsif ($tmpl->{multi}) {
    # multi-value
    my @vals = $running->returnOrigValues($real_path);
    $val = \@vals;
  } else {
    # single-value
    $val = $running->returnOrigValue($real_path);
  }

  if (!defined($href->{type2})) {
    # regular param
    return createTypedParam($tmpl->{type}, $val, $href);
  } else {
    # multi-typed param
    $href->{type} = $tmpl->{type};
    return createMultiTypedParam($val, $href);
  }
}

sub isCustomObj {
  my $obj = shift;
  my $otype = ref($obj);
  return (!($otype =~ /^App::Param::/) or !defined($obj->{DATA})
          or !defined($obj->{DATA}->{param})
          or !JSON::is_bool($obj->{DATA}->{param}));
}

1;

