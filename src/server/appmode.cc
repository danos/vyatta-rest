/**
 * Module: appmode.cc
 * Description: application mode handler for main app mode.
 *
 * Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
 * Copyright (c) 2009-2013 Vyatta, Inc.
 * All Rights Reserved.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 **/

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <signal.h>
#include <syslog.h>
#include <stdlib.h>
#include <stdio.h>
#include <string>
#include <iostream>
#include <unistd.h>
#include <string>
#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <pwd.h>
#include <libaudit.h>
#include "rl_str_proc.hh"
#include "common.hh"
#include "http.hh"
#include "mode.hh"
#include "appmode.hh"
#include "debug.h"

using namespace std;

/**
 * \brief Process an appmode request
 *
 **/
void
AppMode::process(Session &session)
{
	//  Timer t("AppMode::process()");
	dsyslog(_debug, "AppMode:%s: _session_key='%s'", __func__, session._session_key.c_str());
	session.vyatta_debug("XC");

	if (session._auth_type == Rest::AUTH_TYPE_NONE) {
		ERROR(session,Error::AUTHORIZATION_FAILURE);
		return;
	}

	//now build out command
	string path = session._request.get(Rest::HTTP_REQ_URI);
	if (path.empty()) {
		ERROR(session,Error::VALIDATION_FAILURE);
		return;
	}
	string command = path.substr(Rest::APP_REQ_ROOT.length());
	if (command.empty()) {
		ERROR(session,Error::VALIDATION_FAILURE);
		return;
	}

	string environment = "export REQUEST_METHOD=" + session._request.get(Rest::HTTP_REQ_METHOD) + ";";
	environment += "export COMMIT_VIA=gui2_app;";
	if (session._session_key.empty() == false) {
		environment += "export SESSION=" + session._session_key + ";";
	}
	if (session._user.empty() == false) {
		environment += "export USERNAME=" + session._user + ";";
	}

	// TODO: We cannot share the input across all sessions in Redding
	string json = session._request.get(Rest::HTTP_BODY);
	FILE *fd = fopen(Rest::JSON_INPUT.c_str(),"w");
	if (!fd) {
		ERROR(session,Error::SERVER_ERROR);
		return;
	}
	if (fwrite(json.c_str(),sizeof(char),json.size(),fd) < json.size()) {
		fclose(fd);
		ERROR(session,Error::SERVER_ERROR);
		return;
	}
	fclose(fd);

	string appmodecmd = "/bin/bash -p -c '" + environment + "umask 000; source /usr/lib/cgi-bin/vyatta-app;_vyatta_app_run " + command  + " < "+ Rest::JSON_INPUT +"'";
	string stdout;


	//use true id and group in split process here

	{
		//    Timer tt("AppMode::process::execute()");
		int err = 0;
		if ((err = Mode::system_out(appmodecmd.c_str(),stdout)) != 0) {
			ERROR(session,Error::APPMODE_SCRIPT_ERROR);
		}
	}
	if (!_debug) {
		unlink(Rest::JSON_INPUT.c_str());
	}

	Mode::handle_cmd_output(stdout, session);

	dsyslog(_debug, "AppMode:%s: echo XE: '%s'", __func__, appmodecmd.c_str());
	session.vyatta_debug("XE:" + appmodecmd);
	if (_debug) {
		FILE *fp = fopen(Rest::JSON_INPUT.c_str(), "a");
		if (fp) {
			fprintf(fp, "XE: '%s'\n", appmodecmd.c_str());
			fclose(fp);
		}
	}
}

