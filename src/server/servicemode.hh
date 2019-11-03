/**
 * Copyright (c) 2014 by Brocade Communications Systems, Inc.
 * All rights reserved.
 **/

#ifndef __SERVICEMODE_HH__
#define __SERVICEMODE_HH__

#include <string>
#include "http.hh"
#include "mode.hh"

class ServiceMode : protected Mode
{
public:
	ServiceMode(bool debug) : Mode(debug) {};
	~ServiceMode() {};

	void
	process(Session &session);

private:
	void
	service_index(Session &session);

	std::string
	validate_service_cmd(std::string &cmd);

	void
	execute_service(Session &session, std::string &path);

	int
	system_out(const char *cmd, std::string &out);
};

#endif //__SERVICEMODE_HH__
