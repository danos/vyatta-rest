# Module: Rest.pm
# Description: Implements client rest support

# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2017 by Brocade Communications Systems, Inc.
# All Rights Reserved.
# Copyright (c) 2006-2010 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package Vyatta::Rest;
use strict;

use JSON;

sub send_request
{
    my $auth = shift;
    my $http_method = shift;
    my $http_uri = shift;
    my $override_json = shift;
    my $debug = shift;
    my $timeout = shift;
    $timeout = 2 if ! defined $timeout; # default timeout if not specified

    my $code = -1; # no response within timeout [routine specific code]
    my $body;
    my $cmd = "curl --max-time $timeout -k -s -i -H \"authorization: Basic $auth\"  -H \"content-length:0\"  -X $http_method \"$http_uri\"";

    my @out = `$cmd`;
    my $res_output = join(" ", @out);

    if ($res_output =~ /\S/) {
        $code = 200;
        foreach my $out (@out) {
            if ($out =~ /^HTTP\/[\d.]+\s+(\d+)\s+.*$/) {
                $code = $1;
	    }
            elsif ($out =~ /^\r/ || defined $body) {
                $body .= $out;
           }
        }

        if ($debug) {
	    print("\nCOMMAND: $cmd \n");
        }


        #let's convert the body to json, unless requested not to
        if (defined $body && $body !~ /^\r$/) {
            if ($debug) {
                print("\nBODY: $body \n");
	    }

            if ($override_json == 1) {
                return ($code, $body);
	    }
            else {
                my $result;
                eval {$result = from_json($body);};
                if ($@) {
		    $result = undef;
                }
                return ($code, $result);
	    }
        }
        return ($code,undef);
    } # if no non-whitespace characters that means no response received

    return ($code,undef); # no response received, request timed out
}


1;
