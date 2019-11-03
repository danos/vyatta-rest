/**
 * Module: permissions.cc
 * Description: permission request handler
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
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <syslog.h>
#include <iostream>
#include <unistd.h>
#include <string>
#include "http.hh"
#include "common.hh"
#include "configuration.hh"
#include "mode.hh"
#include "permissions.hh"
#include "debug.h"

#include <opd_client.h>
#include <client/connect.h>
#include <client/auth.h>
#include <vyatta-util/map.h>

using namespace std;

Permissions::Permissions(bool debug) : Mode(debug)
{
}

Permissions::~Permissions()
{
}


/**
 * \brief Process a permission request
 * \param[in] session Current gui session
 **/
void
Permissions::process(Session &session)
{
	if (session._auth_type == Rest::AUTH_TYPE_NONE) {
		ERROR(session,Error::AUTHORIZATION_FAILURE);
		return;
	}

	dsyslog(_debug, "Permissions COMMAND");

	//request body contains key, value pairs that need to be passed down as json
	string path = session._request.get(Rest::HTTP_REQ_URI);
	if (path.empty()) {
		session.vyatta_debug("perm:1");
		ERROR(session,Error::VALIDATION_FAILURE);
		return;
	}

	if (path.length() < Rest::PERM_REQ_ROOT.length()) {
		ERROR(session,Error::VALIDATION_FAILURE);
		return;
	}

	string method = session._request.get(Rest::HTTP_REQ_METHOD);
	if (method == "GET") {
		string resp;
		struct configd_conn _conn;
		struct opd_connection _opd_conn;
		json_t *out = json_object();
		struct ::map *perm = NULL;

		if (configd_open_connection(&_conn) == -1) {
			syslog(LOG_ERR, "webgui: Unable to connect to configuration daemon");
		} else {
			perm = configd_auth_getperms(&_conn, NULL);
			configd_close_connection(&_conn);

			json_object_set_new(out, "conf", maptojson(perm));
		}
		if (opd_open(&_opd_conn) == -1) {
			syslog(LOG_ERR, "webgui: Unable to connect to operational daemon");
		} else {
			perm = opd_getperms(&_opd_conn, NULL);
			opd_close(&_opd_conn);

			json_object_set_new(out, "op", maptojson(perm));
		}

		char *buf = json_dumps(out, JSON_COMPACT);
		resp = string(buf);
		free(buf);
		json_decref(out);
		session._response.set(Rest::HTTP_BODY,resp);
	} else {
		//don't recognize method here.
		ERROR(session,Error::VALIDATION_FAILURE);
		return;
	}
}

json_t *
Permissions::maptojson(struct ::map *perm) {
	const char *next = NULL;
	json_t *arr = json_array();
	while ((next = map_next(perm, next))) {
		string entry(next), key, perm, rnum, path;
		size_t pos = entry.find("=");
		if (pos == string::npos) {
			continue;
		}
		key = entry.substr(0, pos);
		perm = entry.substr(pos + 1, entry.length() - pos);
		if (key != "DEFAULT") {
			pos = key.find(":");
			if (pos == string::npos) {
				continue;
			}
			rnum = key.substr(0, pos);
			path = key.substr(pos + 2, entry.length() - pos+1); // separator is ': ' so skip one after pos.
		} else {
			rnum = "10000";
			path = key;
		}
		json_t *obj = json_object();
		json_object_set_new(obj, "rule", json_integer(atoi(rnum.c_str())));
		json_object_set_new(obj, "path", json_string(path.c_str()));
		json_object_set_new(obj, "perms", json_integer(atoi(perm.c_str())));
		json_array_append_new(arr, obj);
	}
	return arr;
}
