/**
 * Module: process.hh
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2009, 2010 Vyatta, Inc.
 * All Rights Reserved.
 * Authors: Michael Larson
 * Date: 2010
 * Description: process dispatcher for mode handlers
 *
 **/

#ifndef __PROCESS_HH__
#define __PROCESS_HH__

#include <string>
#include "http.hh"
#include "appmode.hh"
#include "servicemode.hh"
#include "opmode.hh"
#include "confmode.hh"
#include "permissions.hh"

class Process
{
public:
	Process(bool debug) : _debug(debug),
		_app_mode(debug),
		_service_mode(debug),
		_op_mode(debug),
		_conf_mode(debug),
		_perms(debug)
	{}

	void
	dispatch(Session &session);

private: //variables
	bool _debug;
	AppMode _app_mode;
	ServiceMode _service_mode;
	OpMode _op_mode;
	ConfMode _conf_mode;
	Permissions _perms;
};

#endif //__PROCESS_HH__
