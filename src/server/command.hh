/**
 * Module: command.hh
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2009, 2010 Vyatta, Inc.
 * All Rights Reserved.
 * Authors: Michael Larson
 * Date: 2010
 * Description: command definitions
 *
 **/

#ifndef __COMMAND_HH__
#define __COMMAND_HH__

#include "common.hh"
#include <string>
#include <set>
#include "http.hh"



class Command
{
public:
	Command(bool debug) : _debug(debug) {}

	void
	init();

	bool
	validate(Session &session);

private:
	bool _debug;
	std::string _name;
	Rest::HTTP_METHOD _req_method;
	std::string _req_root_path;
	std::set<std::string> _req_required_headers;
	bool _req_body;

	std::set<std::string> _resp_required_headers;
	bool _resp_body;
};


#endif //__COMMAND_HH__
