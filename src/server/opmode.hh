/**
 * Module: opmode.hh
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2009, 2010 Vyatta, Inc.
 * All Rights Reserved.
 * Authors: Michael Larson
 * Date: 2010
 * Description: operation mode definition support
 *
 **/

#ifndef __OPMODE_HH__
#define __OPMODE_HH__

#include <string>
#include <vector>
#include <set>
#include "http.hh"
#include "mode.hh"

typedef void CURL;


class OpMode : protected Mode
{
public:
	OpMode(bool debug);
	~OpMode();

	void
	process(Session &session);

private:
	bool
	validate_op_cmd(const std::string &cmd, std::string &path);

private: //variables
	CURL *_curl_handle;
};





#endif //__OPMODE_HH__
