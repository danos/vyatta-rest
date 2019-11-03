/**
 * Module: main.cc
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2009, 2010 Vyatta, Inc.
 * All Rights Reserved.
 * Authors: Michael Larson
 * Date: 2010
 * Description: Main entry point for webgui2
 *
 **/

#ifndef __APPMODE_HH__
#define __APPMODE_HH__

#include <string>
#include "http.hh"
#include "mode.hh"

class AppMode : protected Mode
{
public:
	AppMode(bool debug) : Mode(debug) {}
	~AppMode() {}

	void
	process(Session &session);

private:
	int
	system_out(const char *cmd, std::string &out);

private: //variables
};


#endif //__APPMODE_HH__
