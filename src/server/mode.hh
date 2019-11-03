/**
 * Module: mode.hh
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2009, 2010 Vyatta, Inc.
 * All Rights Reserved.
 * Authors: Michael Larson
 * Date: 2010
 * Description: base object definition for major rest modes
 *
 **/

#ifndef __MODE_HH__
#define __MODE_HH__

#include "http.hh"


class Mode
{
public:
	Mode(bool debug) : _debug(debug) {}
	virtual ~Mode() {}

	virtual void
	process(Session &session) = 0;


	/**
	 * Wrapper for system() call. Parameter holds stdout and stderr of the command.
	 * Returns the actual return command of the executed cmd.
	 **/
	static int
	system_out(const char *cmd, std::string &out);
	
	/**
	 * Handle output from app/service commands - e.g. parse header overrides.
	 * And set the given output as session response.
	 **/
	static void
	handle_cmd_output(std::string &cmdout, Session &session);

protected: //variables
	bool _debug;

};

#endif //__MODE_HH__
