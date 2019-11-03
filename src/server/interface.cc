/**
 * Module: interface.cc
 * Description: validation for incoming responses
 *
 * Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
 * Copyright (c) 2009-2013 Vyatta, Inc.
 * All Rights Reserved.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 **/

#include "command.hh"
#include "interface.hh"


/*
representation will look something like (represents the op mode post request below):

<mode name="op">
  <command>
    <name>action</name>
    <request>
      <method>POST</method>
      <path_root>op</path_root>
      <header>
        <required>Accept</required>
        <required>Authorization</required>
        <required>Vyatta-specification-version</required>
      </header>
    </request>
    <response>
      <header>
        <required>Content-Type</required>
        <required>Content-Length</required>
      </header>
      <status>
        <code>201</code>
        <code>400</code>
        <code>401</code>
        <code>403</code>
        <code>404</code>
      </status>
      <body>
      </body>
    </response>
  </command>
</mode>



 */


Command
Interface::initialize(bool debug)
{
	Command cmd(debug);
	//first open file, read and parse data.


	//then used to process incoming message


	return cmd;
}
