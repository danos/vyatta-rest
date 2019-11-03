/**
 * Module: confmode.hh
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2009, 2010 Vyatta, Inc.
 * All Rights Reserved.
 * Authors: Michael Larson
 * Date: 2010
 * Description: Configuration mode definitions
 *
 **/

#ifndef __CONFMODE_HH__
#define __CONFMODE_HH__

#include <string>
#include "http.hh"
#include "mode.hh"

typedef void CURL;

class ConfMode : protected Mode
{
public:
	ConfMode(bool debug);
	~ConfMode();

	void
	process(Session &session);

private:
	bool setup_session(const std::string &sid);
	void
	discard_session(std::string &id, bool exit_session);
	bool is_configd_sess_changed(const std::string &sid);
	std::string conv_url(std::string);

private: //variables
	CURL *_curl_handle;

	const static std::string _shell_env;
};


#endif //__CONFMODE_HH__
