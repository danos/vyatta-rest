/**
 * Module: process.cc
 * Description: implementation of mode dispatcher
 *
 * Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
 * Copyright (c) 2009-2013 Vyatta, Inc.
 * All Rights Reserved.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 **/

#include <stdlib.h>
#include <stdio.h>
#include <string>
#include <iostream>
#include <unistd.h>
#include <string>
#include "process.hh"
#include "debug.h"

using namespace std;

/**
 *
 *
 **/
void
Process::dispatch(Session &session)
{
	//app
	dsyslog(_debug, "%s: XA", __func__);
	session.vyatta_debug("XA");

	//request body contains key, value pairs that need to be passed down as json
	string path = session._request.get(Rest::HTTP_REQ_URI);
	if (path.empty()) {
		//stuff error into     resp. here
		return;
	}
	dsyslog(_debug, "%s: XB:%s", __func__, path.c_str());
	session.vyatta_debug("XB:"+path);

	if (session._access_level == Session::k_VYATTASERVICE_USER) {
		if (path.find(Rest::SERVICE_REQ_ROOT) == 0) {
			_service_mode.process(session);
		} else {
			ERROR(session,Error::VALIDATION_FAILURE);
		}
	} else {
		if (path.find(Rest::APP_REQ_ROOT) == 0) {
			_app_mode.process(session);
		} else if (path.find(Rest::OP_REQ_ROOT) == 0) { //op
			_op_mode.process(session);
		} else if (path.find(Rest::CONF_REQ_ROOT) == 0) { //conf
			_conf_mode.process(session);
		} else if (path.find(Rest::PERM_REQ_ROOT) == 0) { //conf
			_perms.process(session);
		} else {
			ERROR(session,Error::VALIDATION_FAILURE);
		}
	}
}
