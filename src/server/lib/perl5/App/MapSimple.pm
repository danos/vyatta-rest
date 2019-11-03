# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package App::MapSimple;

use strict;
use warnings;

use JSON;

use Data::Dumper;

our @EXPORT = qw(get_map);
use base qw(Exporter);

sub new {
    my (undef,$v) = @_;
    my $self = {};
    $self->{_children} = {};

    foreach my $e (keys %{$v}) {
	set($self,$e,$v->{$e},undef);
    }
    
    #initiate configuration
    bless($self);
    return $self;
}

sub expose {
    my ($self) = @_;
    return $self->{_children};
}

sub attach_absolute {
    my ($self,$name,$child_map) = @_;
    
    my $root = $self->{_children};
    foreach my $e (keys %{$root}) {
	if ($e eq $name) {
	    ${root}->{$e}->{_children} = $child_map->expose();
	}
    }
}

sub attach_relative {
    my ($self,$name,$child_map) = @_;

    my $root = $self->{_children};
    foreach my $e (keys %{$root}) {
	if ($e eq $name) {
	    ${root}->{$e}->{_children} = $child_map->expose();
	}
    }
}

sub set_custom {
    my ($self, $param_name, $cb, $node) = @_;
    
    my $root = $self->{_children};
    if (defined $node) {
	$root = $node->{_children};
    }
    
    $root->{$param_name}->{_callback} = $cb;
    $root->{$param_name}->{_children} = {};
    
    return $root->{$param_name};
}

sub set {
    my ($self, $param_name, $param_loc, $node) = @_;

    my $root = $self->{_children};
    if (defined $node) {
	$root = $node->{_children};
    }

    if (ref($param_loc) eq "CODE") {
	$root->{$param_name}->{_callback} = $param_loc;
    }
    else {
	$root->{$param_name}->{_location} = $param_loc;
    }
    $root->{$param_name}->{_children} = {};
    
    return $root->{$param_name};
}

sub get_map {
    my ($self) = @_;
    my $root = $self->{_children};
    return $root;
}


1;

