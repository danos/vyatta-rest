# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package App::MsgSimple;

use strict;
use warnings;

use JSON;
use App::MapSimple;
use Vyatta::Config;
use Data::Dumper;
use Time::HiRes;

my $CMD_ENV = "export CMD_WRAPPER_SESSION_ID=TEMP_SESSION_$$";
my $CMD_WRAPPER = '/usr/bin/cfgcli -print';
#my $CMD = "$CMD_ENV ; umask 002; sg vyattacfg -c \"$CMD_WRAPPER";


use constant {MAX_MSG_LEN => 512 * 1024};

############################################################################
#
#
#
############################################################################
sub new {
    shift;
    my $map = shift;
    my $debug = shift;
    my $debug_error = shift;
    my $self = {};

    $self->{_map} = $map->get_map();
    $self->{_data} = {};
    $self->{_running} = new Vyatta::Config();
    $self->{_error} = "false";
    $self->{_debug} = $debug;
    $self->{_debug_error} = $debug_error;
    #initiate configuration

    if (defined($self->{_debug})) {
	`echo "TIMING START" > /tmp/rest_msgsimple`;
	$self->{_start} = [ Time::HiRes::gettimeofday( ) ];
    }
    
    bless($self);
    return $self;
}


############################################################################
#
#
#
############################################################################
sub get_value {
    my ($self,$location) = @_;

    #need to add data root in here
    my $droot = $self->{_data};
    my $ct = 0;
    foreach my $elem (@{$location}) {
        $ct++;
        if ($ct % 2) {
            $droot = $droot->{$elem};
        }
        else {
            $droot = $droot->{_values}->{$elem};
        }
    }    
    return keys %{$droot->{_values}};
}

############################################################################
#
#
#
############################################################################
sub set_enum {
    my ($self,$enum,$location) = @_;
    #need to add data root in here
    my $droot = $self->{_data};
    my $ct = 0;
    foreach my $elem (@{$location}) {
        $ct++;
        if ($ct % 2) {
            $droot = $droot->{$elem};
        }
        else {
            $droot = $droot->{_values}->{$elem};

        }
    }
    if (defined $enum) {
        $droot->{_enum} = $enum;
    }
}


############################################################################
#
#
#
############################################################################
sub set_value {
    my ($self,$value,$location) = @_;
    my $ct = 0;
    my @l = @{$location};
    my $size = $#l;

    if (!defined $value) {
	$value = "";
    }

    for (my $k=0; $k<=$size; $k++) {
	if (!($k % 2)) {
	    $ct++;
	    splice(@l,$k+$ct,0,"_values");
	}
    }

    push(@l,$value);
    push(@l,"DUMMY");

    my $r = $self->{_data};
    
    $ct = 0;
    foreach my $elem (@l) {
	$ct++;
	if ($ct < $#l) {
	    if (!defined($r->{$elem}->{$l[$ct]})) {
		$r->{$elem}->{$l[$ct]} = ();
	    }
	}
        if ($ct == $#l) {
            $r->{$value} = ();
        }
	$r = $r->{$elem};
    }
}


############################################################################
#
#
#
############################################################################
sub erase_value {
    my ($self,$location) = @_;
    my $ct = 0;
    my @l = @{$location};
    my $size = $#l;

    for (my $k=0; $k<=$size; $k++) {
	if (!($k % 2)) {
	    $ct++;
	    splice(@l,$k+$ct,0,"_values");
	}
    }

    my $r = $self->{_data};
    $ct = 0;
    foreach my $elem (@l) {
        $ct++;
        if ($ct == ($#l + 1)) {
            delete $r->{$elem};
            last;
        }
        $r = $r->{$elem};
    }
}


############################################################################
#
#
#
############################################################################
sub write_to_configuration {
#run through and perform sets on the data
    my ($self) = @_;
#iterate through _map and retrieve values

    my $start;
    if (defined($self->{_debug})) {
	$start = [ Time::HiRes::gettimeofday( ) ];
    }

    my $in_str = '';
    while (my $line = <STDIN>) {
	$in_str .= $line;
	die 'Input message too long' if (length($in_str) > MAX_MSG_LEN);
    }
    my $data = undef;
    eval { $data = from_json($in_str); };
    if ($@) {
	# "exception"
	die 'Invalid input message';
    }

    my $map_root = $self->{_map};
    $self->{_data} = $data;
    
    #remove root error that is returned via the get on non-compliant configs
    if (defined($self->{_data}->{_error})) {
	delete $self->{_data}->{_error};
    }

    _begin_session();

    if (defined($self->{_debug})) {
	my $elapsed = Time::HiRes::tv_interval( $start );
	`echo "write_to_configuration(A): $elapsed" >> /tmp/rest_msgsimple`;
    }
    $self->_set_elem($map_root,$self->{_data},undef);

    if (defined($self->{_debug})) {
	my $elapsed = Time::HiRes::tv_interval( $start );
	`echo "write_to_configuration(B): $elapsed" >> /tmp/rest_msgsimple`;
    }

#right now suppress on the write, since it will be overwritten anyways.
#    if (_check_commit() == 1) {
#	$self->{_data}->{_error}->{_source} = "";
#	$self->{_data}->{_error}->{_values} = ();
#	$self->{_data}->{_error}->{_description} = "Previous commit was not issued from webgui2 client";
#	$self->{_data}->{_error}->{_code} = "2";
#	$self->{_error} = "true";
#   }

}


############################################################################
#
#
#
############################################################################
sub commit {
    my ($self) = @_;

    my $start;
    if (defined($self->{_debug})) {
	$start = [ Time::HiRes::gettimeofday( ) ];
    }


    my $err = $self->run_cmd("commit_with_error");


    if ($err) {
	$self->_locate_error($err);
    }
    _end_session();

    #for performance return response before save of configuration
    my $pid = fork();
    if( $pid == 0 ){
	if ($err) {
	    _begin_session();
	    $self->run_cmd("load"); #rollback on error
	    $self->run_cmd("commit"); #rollback on error
	    _end_session();
	}
	else {
	    $self->run_cmd("save");
	}
	exit 0;
    }

    if (defined($self->{_debug})) {
	my $elapsed = Time::HiRes::tv_interval( $start );
	`echo "commit(): $elapsed" >> /tmp/rest_msgsimple`;
    }
}

############################################################################
#
#
#
############################################################################
sub run_cmd {
  my ($self,$cmd,$node,$value) = @_;

  my $start;
  if (defined($self->{_debug})) {
      $start = [ Time::HiRes::gettimeofday( ) ];
  }
  my $err = `$CMD_ENV ; umask 002; sg vyattacfg -c \"$CMD_WRAPPER $cmd 2>&1\"`;                                                                                                                                 

  if (defined($self->{_debug})) {
      my $elapsed = Time::HiRes::tv_interval( $start );
      #accumulate set/delete elapsed times
      $self->{_total_elapsed} += $elapsed;

      `echo "run_cmd(): $cmd $elapsed, running total: $self->{_total_elapsed}" >> /tmp/rest_msgsimple`;
  }
  #interpret error and return
  my $resp_code = ($? >> 8);
  if ($resp_code && defined($err) && $err ne "") {
      #now parse output
      my $err_hash = ();
      $err_hash->{_source} = $err;
      $err_hash->{_values} = ();

      #remove err_loc from $err for now and plop into description field
      my @lines = split('\n',$err);
      pop(@lines); #and the last line: commit or set
      if ($err =~ /_errloc_:\[.*\]/) {
	  shift(@lines);
      }
      $err_hash->{_description} = join("\n",@lines);
      $err_hash->{_code} = "";
      if (defined($node) && defined($value)) {
	  $node->{$value}->{_error} = $err_hash;
      }

#      $self->{_error}->{_debug0} = $err;
#      $self->{_error}->{_debug1} = $cmd;

      $self->{_error} = "true";
      return $err_hash;
  }
  return undef;
}

############################################################################
#
#
#
############################################################################
sub set_error {
    my ($self,$loc,$err) = @_;

    #need to add data root in here
    my $droot = $self->{_data};
    my $ct = 0;
    foreach my $elem (@{$loc}) {
        $ct++;
        if ($ct % 2) {
            $droot = $droot->{$elem};
        }
        else {
            $droot = $droot->{_values}->{$elem};
        }
    }    

    $droot->{_error}->{_source} = $err;
    $droot->{_error}->{_values} = ();
    $droot->{_error}->{_description} = $err;
    $droot->{_error}->{_code} = "";
    $self->{_error} = "true";
}

############################################################################
#
#
#
############################################################################
sub read_from_configuration {
    my ($self) = @_;
#iterate through _map and retrieve values
    if (_check_commit() == 1) {
	$self->{_data}->{_error}->{_source} = "";
	$self->{_data}->{_error}->{_values} = ();
	$self->{_data}->{_error}->{_description} = "Previous commit was not issued from webgui2 client";
	$self->{_data}->{_error}->{_code} = "2";
	$self->{_error} = "true";
    }

    my $start;
    if (defined($self->{_debug})) {
	$start = [ Time::HiRes::gettimeofday( ) ];
    }

    my $map_root = $self->{_map};
    my $data_root = $self->{_data};
    my @root;
    push(@root,"data");
    $self->_get_elem($map_root,$data_root,undef,\@root);
    if (defined($self->{_debug})) {
	my $elapsed = Time::HiRes::tv_interval( $start );
	`echo "read_from_configuration(): $elapsed" >> /tmp/rest_msgsimple`;
    }

}

############################################################################
#
#
#
############################################################################
sub send {
  my $self = shift;

  #scrub data
  $self->_scrub_elem($self->{_data});

  print to_json($self->{_data}, {pretty => 1});

  if (defined($self->{_debug})) {
      my $elapsed = Time::HiRes::tv_interval( $self->{_start} );
      `echo "  _OVERALL: $elapsed" >> /tmp/rest_msgsimple`;
  }

  if ($self->{_error} eq "true") {
      exit(100); #overload response code from 100 to 400
  }
}


############################################################################
#
#
#
############################################################################
sub _locate_error {
    my ($self,$err) = @_;
    
    my $m = $self->{_map};
    my $d = $self->{_data};

    my $handled = 1;
    #process each error
    my @lines = split('\n',$err->{_source});
    foreach my $line (@lines) {
        if ($line =~ /_errloc_:\[.*\]$/) {
	    my @el = split(/([\[\]])/,$line);
	    my $error_loc = $el[2];

#don't need to do the following as commit will be converted to space delimited
#	    $error_loc =~ s/\// /g; #slash to space
	    $error_loc =~ s/^\s+//;
	    my $error_msg = $err;
	    #print "working on: $error_loc \n";
	    $handled = $self->_find_error($m,$d,$error_loc,$error_msg);
		#one problem here is that there will only be room for a single error at root, 
		#but this shouldn't really occur.
		
	}
    }
    if ($handled == 1) {
	$self->{_data}->{_error} = $err;
    }
}


############################################################################
#
#
#
############################################################################
sub _find_error {
    my ($self,$m,$d,$err_loc,$err_msg) = @_;

#    print Dumper($m);
#    print Dumper($d);
#    print $err_loc . "\n";
#    print $err_msg . "\n";

    if (!defined($err_loc) || $err_loc eq "" || $err_loc eq "value:") {
	#insert error here and return
	$d->{_error} = $err_msg;	
	return 0;
    }

# 1. check map for match against loccation 
# 2. full match then recurse with location->_values and check data for value match
# 3. partial match insert error and return.
# 4. no match throw at root.
#
    if (defined $m->{_children}) {
	#look for match in value on the data side
	foreach my $elem (keys %{$d}) {
	    my $regex_match = "^$elem(.*)";
	    if ($err_loc =~ m/$regex_match/g) {
		my $remainder = $1;
		$remainder =~ s/^.//s; #strip first char                   
		return $self->_find_error($m->{_children},$d->{$elem},$remainder,$err_msg);
	    }
	}
    }
    else {
	foreach my $elem (keys %{$m}) {
	    my $param_loc = $m->{$elem}->{_location};
	    if (defined($param_loc)) {
		#need to work on a partial match here
#		print "checking partial match: >$param_loc< to >$err_loc< \n";
		my $regex_match = "^$param_loc(.*)";
		if ($err_loc =~ m/$regex_match/g) {
		    my $remainder = $1;
		    $remainder =~ s/^.//s; #strip first char                                                                                                          
		    #lop off the portion that match and continue search unless at an end
#		print "matching: >$param_loc< to >$err_loc< with remainder: $remainder\n";
		    my @v = split(" ",$remainder);
		    if ($#v == 0 || !defined($remainder) || $remainder eq "") {
#		    print "full match\n";
			#exact match... stop
			$d->{$elem}->{_error} = $err_msg;
			if (defined($remainder)) {
			    $d->{$elem}->{_values}->{$remainder} = ();
			}
			return 0;
		    }
		    else {
#		    print "missed \n";
			#continue search
			return $self->_find_error($m->{$elem},$d->{$elem}->{_values},$remainder,$err_msg);
		    }
		}
	    }
	}
    }
    return 1;
}


############################################################################
#
#
#
############################################################################
sub _get_elem {
    my ($self,$m,$d,$loc,$path) = @_;

    #DO THE CALLBACK_FIRST CALL HERE!
    if (defined($m->{callback_first})) {
	my $elem = "callback_first";
	my @p = @$path;
	push(@p,$elem);
	
	my $h = {location => $loc,
		 values => undef,
		 enum => undef};
	if (!defined($d->{$elem})) {
	    _create_data_node($d->{$elem},undef,undef,\@p);
	}
	
	my $start;
	if (defined($self->{_debug})) {
	    $start = [ Time::HiRes::gettimeofday( ) ];
	}
	
	$m->{$elem}->{_callback}("GET",$self->{_running},$h);
	
	
	if (defined($self->{_debug})) {
	    my $elapsed = Time::HiRes::tv_interval( $start );
	    if (defined($loc)) {
		`echo "callback for: $loc: $elapsed" >> /tmp/rest_msgsimple`;
	    }
	    else {
		`echo "callback for: [undefined]: $elapsed" >> /tmp/rest_msgsimple`;
	    }
	}
	
	if (defined($h->{values})) {
	    my $val = $h->{values};
	    foreach my $v (@$val) {
		if (defined($v)) {
		    if (!defined($d->{$elem})) {
			$d->{$elem}->{_values} = ();
			$d->{$elem}->{_parent} = \@p;
		    }
		    _create_data_node($d->{$elem},$h->{enum},$v,[@p]);
		}
	    }
	}
    }

    #iterate over each element in the map
    foreach my $elem (keys %{$m}) {
	my @p = @$path;
	push(@p,$elem);

	my $param_loc = $m->{$elem}->{_location};
	if (!defined($param_loc)) {
	    $param_loc = "";
	}
	my $val = undef;
	#if a location is provide need to grab from configuration tree
	if (defined $param_loc && $param_loc ne "") {

	    #parameter matching up tree--special value handling: ($VALUE)
	    while ($param_loc =~ m/\$(.*?)\)/g) {
#                print("parameter repalcement on $param_loc: $1 \n");
		my $match = $1;
#		print Dumper($d);
#                print Dumper($m);
#                print Dumper($loc);
		my $ct = 0;
                foreach my $p (@p) {
		    $ct++;
		    if ($p eq $match) {
#			print "found match!: $p\n";
#			print "--->$p[$ct+1]\n";
			my $found = $p[$ct];
			_create_data_node($d->{$elem},undef,$found,[@p]);
			last;
		    }
		}
#		print Dumper($d);
#		exit(1);

	    }
	    if (defined $loc) {
		$param_loc = $loc . " " . $param_loc;
	    }
	    my $tmpl = $self->{_running}->parseTmplAll($param_loc);
	    $val = $self->_get_values($tmpl,$param_loc);

	    if (!defined($d->{$elem})) {
		$d->{$elem}->{_values} = ();
		$d->{$elem}->{_parent} = \@p;
	    }
	    _create_data_node($d->{$elem},_generate_enum($tmpl->{allowed}),undef,undef);
	    _create_data_node($d->{$elem},_process_val_help($tmpl->{val_help}),undef,undef);

	    foreach my $v (@$val) {
		if (defined $v) {
		    _create_data_node($d->{$elem},undef,$v,[@p]);
		}
	    }
	}
	elsif (defined $m->{$elem}->{_callback}) {
	    if ($elem eq "callback_first" || $elem eq "callback_last") {
      	        #NEED TO DEFINE SPECIAL CALLBACKS: CALLBACK_FIRST, AND HIDDEN-LAST
	        #
                #callback_first is called at beginning of the group
	        #callback_last is called at the end fo the group
		next;
	    }

	    my $h = {location => $loc,
		     values => undef,
		     enum => undef};
	    if (!defined($d->{$elem})) {
		_create_data_node($d->{$elem},undef,undef,\@p);
	    }

	    my $start;
	    if (defined($self->{_debug})) {
		$start = [ Time::HiRes::gettimeofday( ) ];
	    }

	    $m->{$elem}->{_callback}("GET",$self->{_running},$h);

	    
	    if (defined($self->{_debug})) {
		my $elapsed = Time::HiRes::tv_interval( $start );
		if (defined($loc)) {
		    `echo "callback for: $loc: $elapsed" >> /tmp/rest_msgsimple`;
		}
		else {
		    `echo "callback for: [undefined]: $elapsed" >> /tmp/rest_msgsimple`;
		}
	    }

	    if (defined($h->{values})) {
		$val = $h->{values};
		foreach my $v (@$val) {
		    if (defined($v)) {
			if (!defined($d->{$elem})) {
			    $d->{$elem}->{_values} = ();
			    $d->{$elem}->{_parent} = \@p;
			}
			_create_data_node($d->{$elem},$h->{enum},$v,[@p]);
		    }
		}
	    }
	}

	#at this point we have the values and enumeration for this field
	#iff $param_loc is defined, regardless we need to create a spot

	#we've found values, now let's enter recursion
	if (defined $val) {
	    foreach my $v (@$val) {
		if (!defined($v)) {
		    next;
		}
		#look at map for nested elements
		foreach my $c ($m->{$elem}->{_children}) {
		    if (%$c) {
			foreach my $e (keys %{$c}) {
			    $d->{$elem}->{_parent} = \@p;
			    _create_data_node($d->{$elem}->{_values}->{$v}->{$e}->{_values},undef,undef,[@p,$v,$e]);
		        }
                        my $pl = $param_loc . " " . $v; #add multi value
			if ($param_loc eq "") {
			    $pl = "";
			}

		        my @ppp = @p;
		        push(@ppp,$v);
			push(@ppp,"_values");
                        $self->_get_elem($c,$d->{$elem}->{_values}->{$v},$pl,\@ppp);
		    }
		}
	    }
	}
    }

    #DO THE CALLBACK_LAST CALL HERE!
    #DO THE CALLBACK_FIRST CALL HERE!
    if (defined($m->{callback_last})) {
	my $h = {location => $loc,
		 values => undef,
		 enum => undef};
	my $elem = "callback_last";
	my @p = @$path;
	push(@p,$elem);
	if (!defined($d->{$elem})) {
	    _create_data_node($d->{$elem},undef,undef,\@p);
	}
	
	my $start;
	if (defined($self->{_debug})) {
	    $start = [ Time::HiRes::gettimeofday( ) ];
	}
	
	$m->{$elem}->{_callback}("GET",$self->{_running},$h);
	
	
	if (defined($self->{_debug})) {
	    my $elapsed = Time::HiRes::tv_interval( $start );
	    if (defined($loc)) {
		`echo "callback for: $loc: $elapsed" >> /tmp/rest_msgsimple`;
	    }
	    else {
		`echo "callback for: [undefined]: $elapsed" >> /tmp/rest_msgsimple`;
	    }
	}
	
	if (defined($h->{values})) {
	    my$val = $h->{values};
	    foreach my $v (@$val) {
		if (defined($v)) {
		    if (!defined($d->{$elem})) {
			$d->{$elem}->{_values} = ();
			$d->{$elem}->{_parent} = \@p;
		    }
		    _create_data_node($d->{$elem},$h->{enum},$v,[@p]);
		}
	    }
	}
    }


}


############################################################################
#
#
#
############################################################################
sub _get_values 
{
    my ($self, $tmpl, $param_loc) = @_;
    
    my $val = undef;
    #now find location
    if ($tmpl->{multi}) {
	# multi-value
	my @vals = $self->{_running}->returnOrigValues($param_loc);
	$val = \@vals;
    } elsif ($tmpl->{tag}) {
	my @vals = $self->{_running}->listOrigNodes($param_loc);
	$val = \@vals;
    } else {
	# single-value
	$val = [$self->{_running}->returnOrigValue($param_loc)];
    }
    return $val;
}


############################################################################
#
#
#
############################################################################
sub _set_elem {
    my ($self,$m,$d,$loc) = @_;

    #DO THE CALLBACK_FIRST CALL HERE!
    if (defined($m->{callback_first})) {
	my $start;
	if (defined($self->{_debug})) {
	    $start = [ Time::HiRes::gettimeofday( ) ];
	}
	#rework $parms to be an array that is passed down and pushed into...
	my $h = {location => $loc,
		 values => undef,
		 enum => undef};
	$m->{callback_first}->{_callback}("POST",$self->{_running},$h);
	#position for callback method
	#NEED TO HANDLE ERRORS HERE
	if (defined($self->{_debug})) {
	    my $elapsed = Time::HiRes::tv_interval( $start );
	    if (defined($loc)) {
		`echo "  _set_elem(B): for $loc: $elapsed" >> /tmp/rest_msgsimple`;
	    }
	    else {
		    `echo "  _set_elem(B): for [undefined]: $elapsed" >> /tmp/rest_msgsimple`;
	    }
	}
    }

    #iterate over each element in the map
    foreach my $elem (keys %{$m}) {
	my $param_loc = $m->{$elem}->{_location};
	my $val = $d->{$elem}->{_values};
	#if a location is provide need to grab from configuration tree
	if (defined $param_loc) {
	    if (defined $loc) {
		$param_loc = $loc . " " . $param_loc;
	    }

            #parameter matching up tree--special value handling: ($VALUE)
            if ($param_loc =~ m/\$(.*?)\)/g) {
		#skip this for now
		next;
	    }

	    my $start;
	    if (defined($self->{_debug})) {
		$start = [ Time::HiRes::gettimeofday( ) ];
	    }

	    #SPECIAL CASE--for multi's remove all entries then reapply
	    #if this node is a multi, then delete first

	    my $tmpl = $self->{_running}->parseTmplAll($param_loc);

	    #reconcile tag nodes against form
	    #NEED TO CHECK SYSTEM AND "DELETE" MULTIS THAT DON'T EXIST IN CURRENT SET...
	    if ($tmpl->{tag}) {
		#at this point look at tag nodes under $param_loc and remove any that exist in configuration but not in request
		my @conf_nodes = $self->{_running}->listOrigNodes($param_loc);
		my @form_nodes = keys %{$val};

		my %diff;
		@diff{ @conf_nodes } = @conf_nodes;
		delete @diff{ @form_nodes };
		foreach my $k (keys %diff) {
		    $self->run_cmd("delete $param_loc $k",$d->{$elem}->{_values},$k);
		}

		@diff{ @form_nodes } = @form_nodes;
		delete @diff{ @conf_nodes };
		foreach my $k (keys %diff) {
		    $self->run_cmd("set $param_loc $k",$d->{$elem}->{_values},$k);
		}
	    }
	    elsif ($tmpl->{multi}) {
		#figure out difference before applying
		my @conf_nodes = $self->{_running}->returnOrigValues($param_loc);
		my @form_nodes = keys %{$val};

		my %diff;
		@diff{ @conf_nodes } = @conf_nodes;
		delete @diff{ @form_nodes };
		foreach my $k (keys %diff) {
		    $self->run_cmd("delete $param_loc $k",$d->{$elem}->{_values},$k);
		}

		@diff{ @form_nodes } = @form_nodes;
		delete @diff{ @conf_nodes };
		foreach my $k (keys %diff) {
		    $self->run_cmd("set $param_loc $k",$d->{$elem}->{_values},$k);
		}
	    }
	    else {
		my @v = keys %{$val};
		my $val = $v[0];
		if (defined($val)) {
		    $val =~ s/\s+$//; #strip trailing spaces
		}
		if ($#v == -1 || !defined($val) || $val eq "") {
		    $self->run_cmd("delete " . $param_loc,$d->{$elem});
		}
		else {
		    if (!$self->{_running}->existsOrig($param_loc . " " . $val)) {
			if ($v[0] =~ / /) {
			    $self->run_cmd("set " . $param_loc . " \\\"" . $val . "\\\"",$d->{$elem}->{_values},$val);
			}
			else {
			    $self->run_cmd("set " . $param_loc . " " . $val,$d->{$elem}->{_values},$val);
			}
		    }
		}
	    }

	    if (defined($self->{_debug})) {
		my $elapsed = Time::HiRes::tv_interval( $start );
		`echo "  _set_elem(A): for $param_loc: $elapsed" >> /tmp/rest_msgsimple`;
	    }

	}
	elsif (defined $m->{$elem}->{_callback}) {
	    #don't process these special callbacks here...
	    if ($elem eq "callback_first" || $elem eq "callback_last") {
      	        #NEED TO DEFINE SPECIAL CALLBACKS: CALLBACK_FIRST, AND HIDDEN-LAST
	        #
                #callback_first is called at beginning of the group
	        #callback_last is called at the end fo the group
		next;
	    }


	    my $start;
	    if (defined($self->{_debug})) {
		$start = [ Time::HiRes::gettimeofday( ) ];
	    }
	    #rework $parms to be an array that is passed down and pushed into...
	    my $h = {location => $loc,
		     values => $d->{$elem}->{_values},
		     enum => undef};
	    $m->{$elem}->{_callback}("POST",$self->{_running},$h);
	    #position for callback method
	    #NEED TO HANDLE ERRORS HERE
	    if (defined($self->{_debug})) {
		my $elapsed = Time::HiRes::tv_interval( $start );
		if (defined($loc)) {
		    `echo "  _set_elem(B): for $loc: $elapsed" >> /tmp/rest_msgsimple`;
		}
		else {
		    `echo "  _set_elem(B): for [undefined]: $elapsed" >> /tmp/rest_msgsimple`;
		}
	    }
	}

	#at this point we have the values and enumeration for this field
	#iff $param_loc is defined, regardless we need to create a spot

	#we've found values, now let's enter recursion
	if (defined $val) {
	    foreach my $v (keys %{$val}) {
		#look at map for nested elements
		foreach my $c ($m->{$elem}->{_children}) {
		    if (%$c && defined($param_loc)) {
			my $pl = $param_loc . " " . $v; #add multi value
			$self->_set_elem($c,$d->{$elem}->{_values}->{$v},$pl);
		    }
		}
	    }
	}
    }

    #DO THE CALLBACK_LAST CALL HERE!
    if (defined($m->{callback_last})) {
	my $start;
	if (defined($self->{_debug})) {
	    $start = [ Time::HiRes::gettimeofday( ) ];
	}
	#rework $parms to be an array that is passed down and pushed into...
	my $h = {location => $loc,
		 values => undef,
		 enum => undef};
	$m->{callback_last}->{_callback}("POST",$self->{_running},$h);
	#position for callback method
	#NEED TO HANDLE ERRORS HERE
	if (defined($self->{_debug})) {
	    my $elapsed = Time::HiRes::tv_interval( $start );
	    if (defined($loc)) {
		`echo "  _set_elem(B): for $loc: $elapsed" >> /tmp/rest_msgsimple`;
	    }
	    else {
		    `echo "  _set_elem(B): for [undefined]: $elapsed" >> /tmp/rest_msgsimple`;
	    }
	}
    }

}

############################################################################
#
#
#
############################################################################
sub _check_commit {
    my $out = `/usr/sbin/chunker2_cmd "show system commit" 2>/dev/null`;
    my @lines = split('\n',$out);
    my $first_line = $lines[0];
    #no error if client was gui2_app, or there are only two entries
    if ($first_line =~ /gui2_app/ || $#lines <= 2) {
	return 0;
    }
    return 1;
}


############################################################################
#
# set up a config session.
# returns error message or undef if sucessful.
#
############################################################################
sub _begin_session {
  my $err = `$CMD_ENV ; umask 002; sg vyattacfg -c \"cli-shell-api setupSession 2>&1\"`;
  return "Cannot set up config session: $err" if ($? >> 8);
  return undef;
}

############################################################################
#
# tear down a config session.
# returns error message or undef if sucessful.
#
############################################################################
sub _end_session {
  my $err = `$CMD_ENV ; umask 002; sg vyattacfg -c \"cli-shell-api teardownSession 2>&1\"`;
  return "Cannot tear down config session: $err" if ($? >> 8);
  return undef;
}

############################################################################
#
#
#
############################################################################
sub _generate_enum {
  my $script = shift;
  if (!defined $script) {
      return;
  }
#  my @a = split(' ',$script);
#  if (! -f "$a[0]" or ! -e "$a[0]") {
#      return;
#  }
  my $out = `$script 2>/dev/null`;
  chomp($out);
  return _parse_enum_out($out);
}

############################################################################
#
#
#
############################################################################
sub _process_val_help {
  my $out = shift;
  if (!defined($out)) {
      return ();
  }
  my @array = ();
  if ($out =~ /\n/) {
    @array = split /\n/, $out;
  } else {
    @array = split /\s/, $out;
  }
  
  my $ct = 0;
  foreach my $v (@array) {
      my @a = split(/;/,$v);
      $array[$ct] = $a[0];
      $ct += 1;
  }

  return \@array;
}


############################################################################
#
#
#
############################################################################
sub _parse_enum_out {
  my $out = shift;
  my @array = ();
  $out =~ s/'//g;
  if ($out =~ /\n/) {
    @array = split /\n/, $out;
  } else {
    @array = split /\s/, $out;
  }
  return \@array;
}

############################################################################
#
#
#
############################################################################
sub _create_data_node {
    my ($d,$e,$v,$p) = @_;
    if (!defined($d->{_enum})) {
	$d->{_enum} = $e;
    }
    if (defined($v)) {
	$d->{_values}->{$v} = ();
    }
    if (!defined($d->{_parent})) {
	$d->{_parent} = $p;
    }
}

############################################################################
#
#
#
############################################################################
sub _scrub_elem {
    my ($self, $node) = @_;
    if (ref($node) ne "HASH") {
	return;
    }
    foreach my $elem (keys %{$node}) {
	if (!defined($elem)) {
	    return;
	}
	elsif ($elem eq "_parent") {
	    delete $node->{$elem};
	    next;
	}
	elsif ($elem eq "callback_first") {
	    delete $node->{$elem};
	    next;
	}
	elsif ($elem eq "callback_last") {
	    delete $node->{$elem};
	    next;
	}
	#insert debug error messages
	if (defined($self->{_debug_error})) {
	    if ($elem eq "_values") {
		my $err_hash = ();
		$err_hash->{_source} = "DUMMY";
		$err_hash->{_description} = $elem;
		$err_hash->{_code} = "1";
		$node->{_error} = $err_hash;
	    }
	}

	$self->_scrub_elem($node->{$elem});
    }
}


1;

