#! /usr/bin/perl
#
# Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2014 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use warnings;
use CGI;

my $q = CGI->new();
print $q->header(-status=>'403 Forbidden');

my $error = '
<?xml version="1.0" encoding="iso-8859-1"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
         "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
 <head>
  <title>Service disabled</title>
 </head>
 <body>
  <h1>Service disabled</h1>
 </body>
</html>';

print $error;

exit 0;

