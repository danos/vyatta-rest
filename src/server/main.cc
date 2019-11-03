/**
 * Module: main.cc
 * Description: main entry point for webgui2 cgi
 *
 * Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
 * Copyright (c) 2009-2013 Vyatta, Inc.
 * All Rights Reserved.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 **/

#include <libaudit.h>
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
#include <fcgi_stdio.h>
#include <pwd.h>
#include <fcntl.h>
#include "common.hh"
#include "http.hh"
#include "command.hh"
#include "process.hh"
#include "authenticate.hh"
#include "interface.hh"
#include "debug.h"

#define RUNDIR "/run/vyatta-webgui2"

using namespace std;

bool
parse(Session &session);

uid_t g_uid;
gid_t g_gid;


static void dump_env(void)
{
	static const char envfile[] = "/tmp/environ";
	FILE *pf;

	pf = fopen(envfile, "w");
	if (!pf)
		return;
	for (unsigned int i = 0; environ[i]; ++i)
		fprintf(pf, "%s\n", environ[i]);
	fclose(pf);
}

static int mkrundir(void)
{
	struct stat rundir;
	if (stat(RUNDIR, &rundir) != 0) {
		return mkdir(RUNDIR, S_IRWXU | S_IRWXG);
	}
	if (!S_ISDIR(rundir.st_mode)) {
		return -1;
	}
	return 0;
}

/**
 *
 * Main entry...
 *
 **/
int
main(int argc, char* argv[])
{
	bool debug = false;

	openlog("rest", LOG_PID, LOG_DAEMON);

	syslog(LOG_INFO, "REST server starting");
	if (mkrundir() != 0) {
		syslog(LOG_INFO, "Missing %s directory", RUNDIR);
	}

	//set flag for debug on whether $RUNDIR/debug_webgui2 file is found
	struct stat tmp;
	if (stat(RUNDIR "/debug_webgui2", &tmp) == 0) {
		syslog(LOG_NOTICE, "Enabling debug mode");
		debug = true;
	}

	Command cmds = Interface::initialize(debug);

	g_gid = getgid();
	g_uid = getuid();

	umask(002);

	Authenticate auth(debug);

	unsigned long ct = 0;
	while (FCGI_Accept() >= 0) {
		string out;
		Session session(debug);
		Process proc(debug);
		++ct;

		//let's fix the content-type for now
		session._response.set(Rest::HTTP_RESP_CONTENT_TYPE, "application/json");
		session._response.set(Rest::HTTP_RESP_VYATTA_SPECIFICATION_VERSION, Rest::REST_SERVER_VERSION);

		//disable client side caching
		session._response.set(Rest::HTTP_RESP_CACHE_CONTROL, "no-cache");

		dsyslog(debug, "%s: 1", __func__);
		if (debug)
			dump_env();

		dsyslog(debug, "%s: A", __func__);
		session.vyatta_debug("A");

		if (parse(session) == false) {
			proc.dispatch(session);
			FCGI_printf("%s",session._response.serialize().c_str());
			goto done;
		}

		dsyslog(debug, "%s: B", __func__);
		session.vyatta_debug("B");

		dsyslog(debug, "%s: C", __func__);
		session.vyatta_debug("C");

		//authenticate
		if (cmds.validate(session) == false) {
			//will generate errors then....
			FCGI_printf("%s",session._response.serialize().c_str());
			goto done;
		}

		dsyslog(debug, "%s: D", __func__);
		session.vyatta_debug("D");

		//authorize command here
		if (auth.validate(session) == false) {
			dsyslog(debug, "%s: AUTHFAILED: %s", __func__, session._response.serialize().c_str());

			if (session._request.get(Rest::HTTP_REQ_URI).find(Rest::APP_REQ_ROOT) != 0) {
				//non-standard for 401, but allows client application to capture control & redirect

				//remove this to allow client code in browser to handle response
				//	session._response.set(Rest::HTTP_RESP_WWWAUTH,"Basic realm=\"Secure Area\"");
			}

			ERROR(session,Error::AUTHORIZATION_FAILURE);
			FCGI_printf("%s",session._response.serialize().c_str());
			goto done;
		}

		dsyslog(debug, "%s: E", __func__);
		session.vyatta_debug("E");

		//dispatch
		proc.dispatch(session);
		out = session._response.serialize();
		FCGI_fwrite((void *) out.data(), 1, out.length(), FCGI_stdout);

		if (debug) {
			FILE *fp = fopen("/tmp/rest_out","a");
			if(fp) {
				fwrite(out.data(), 1, out.length(), fp);
				fclose(fp);
			}
		}

	done:
		FCGI_Finish();
		setuid(g_uid);
		setgid(g_gid);
		if (audit_setloginuid(g_uid) < 0) {
			syslog(LOG_ERR, "Failed to reset loginuid\n");
		}
	}

	return 0;
}

/**
 *
 *
 **/
bool
parse(Session &session)
{
	session._request.set(Rest::HTTP_REQ_URI,getenv("REQUEST_URI"));
	session._request.set(Rest::HTTP_REQ_QUERY_STRING,getenv("QUERY_STRING"));
	session._request.set(Rest::HTTP_REQ_METHOD,getenv("REQUEST_METHOD"));
	session._request.set(Rest::HTTP_REQ_ACCEPT,getenv("ACCEPT"));
	session._request.set(Rest::HTTP_REQ_CONTENT_LENGTH,getenv("CONTENT_LENGTH"));
	session._request.set(Rest::HTTP_REQ_AUTHORIZATION,getenv("HTTP_AUTHORIZATION"));
        session._request.set(Rest::HTTP_REQ_COOKIE,getenv("HTTP_COOKIE"));
	session._request.set(Rest::HTTP_REQ_VYATTA_SPECIFICATION_VERSION,getenv("VYATTA_SPECIFICATION_VERSION"));
	session._request.set(Rest::HTTP_REQ_ACCEPT,getenv("ACCEPT"));
	session._request.set(Rest::HTTP_REQ_HOST,getenv("HOST"));
	session._request.set(Rest::HTTP_REQ_PRAGMA,getenv("HTTP_PRAGMA"));


	//now retrieve the body of the request
	string slen = session._request.get(Rest::HTTP_REQ_CONTENT_LENGTH);
	if (slen.empty() == false) {
		unsigned long len = strtoul(slen.c_str(),NULL,10);
		if (len > Rest::MAX_BODY_SIZE || len < 0) {
			Error(session,Error::VALIDATION_FAILURE,"Request body exceeds maximum allowable size");
			return false;
		}

		string tmp;
		for (unsigned long i = 0; i < len; ++i) {
			int ch;
			if ((ch = FCGI_getchar()) < 0) {
				break;
			}
			tmp += char(ch);
		}
		session._request.set(Rest::HTTP_BODY,tmp);
	}
	return true;
}
