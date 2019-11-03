/**
 * Module: opmode.cc
 * Description: operational mode command handler
 *
 * Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
 * Copyright (c) 2009-2013 Vyatta, Inc.
 * All Rights Reserved.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 *
 **/

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <syslog.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <iostream>
#include <unistd.h>
#include <curl/curl.h>
#include <vector>
#include <string>
#include <dirent.h>
#include "http.hh"
#include "multirespcmd.hh"
#include "rl_str_proc.hh"
#include "common.hh"
#include "configuration.hh"
#include "mode.hh"
#include "opmode.hh"
#include "debug.h"

#include <vyatta-util/vector.h>

using namespace std;

OpMode::OpMode(bool debug) : Mode(debug)
{
	_curl_handle = curl_easy_init();
}

OpMode::~OpMode()
{
	curl_easy_cleanup(_curl_handle);
}


/**
 * \brief Process a operational mode request
 * \param[in] session Current gui session
 **/
void
OpMode::process(Session &session)
{
	if (session._auth_type == Rest::AUTH_TYPE_NONE) {
		ERROR(session,Error::AUTHORIZATION_FAILURE);
		return;
	}

	dsyslog(_debug, "OPMODE COMMAND");

	//request body contains key, value pairs that need to be passed down as json
	string path = session._request.get(Rest::HTTP_REQ_URI);
	if (path.empty()) {
		session.vyatta_debug("op:1");
		ERROR(session,Error::VALIDATION_FAILURE);
		return;
	}

	if (path.length() < Rest::OP_REQ_ROOT.length()) {
		ERROR(session,Error::VALIDATION_FAILURE);
		return;
	}

	string method = session._request.get(Rest::HTTP_REQ_METHOD);
	//////////////////////////////////////////////////////////////////////////////////
	//
	//   POST COMMAND TO OP MODE
	//
	//////////////////////////////////////////////////////////////////////////////////
	if (method == "POST") {
		dsyslog(_debug, "POST COMMAND");

		if (path.length() <= Rest::OP_REQ_ROOT.length()) {
			ERROR(session,Error::VALIDATION_FAILURE);
			return;
		}

		string cmd = path.substr(Rest::OP_REQ_ROOT.length()+1);
		cmd = Rest::translate_rest_to_cli(_curl_handle,cmd);
		/*
		cmd = Rest::mass_replace(cmd,"/"," ");
		cmd = Rest::mass_replace(cmd,"%2F","/");
		cmd = Rest::mass_replace(cmd,"%2f","/");
		*/

		//start a process here
		MultiResponseCommand op_cmd(_debug);
		if (op_cmd.init() == false) {
			session.vyatta_debug("op:chunker init failed");
			ERROR(session,Error::SERVER_ERROR);
			return;
		}

		dsyslog(_debug, "Command: %s", cmd.c_str());
		string id = op_cmd.start(session._user,cmd);
		if (id.empty()) {
			ERROR(session,Error::SERVER_ERROR);
			return;
		}

		string location = string("rest/op/")+id;
		session._response.set(Rest::HTTP_RESP_LOCATION,location);
		session.vyatta_debug("op:1.2");
		ERROR(session,Error::CREATED);
		return;
	} else if (method == "GET") {
		string op_path;

		//////////////////////////////////////////////////////////////////////////////////
		//
		//   GET LISTING OF BACKGROUND PROCESSES
		//
		//////////////////////////////////////////////////////////////////////////////////
		if (path == Rest::OP_REQ_ROOT) {
			//gets list of background processes
			MultiResponseCommand op_cmd(_debug);
			if (op_cmd.init() == false) {
				session.vyatta_debug("op:chunker init failed");
				ERROR(session,Error::SERVER_ERROR);
				return;
			}

			std::vector<ProcessData> coll = op_cmd.get_processes(session._user);
			//now serialize this into the body

			JSON json;
			if (!coll.empty()) {
				std::vector<ProcessData>::iterator iter = coll.begin();
				while (iter != coll.end()) {
					//build out the json resp string here.
					string ttmp = "{\"username\":\"" + iter->_username + "\",";
					char buf[80];
					sprintf(buf,"%ld",iter->_start_time);
					ttmp += "\"started\":\"" + string(buf) + "\",";
					sprintf(buf,"%ld",iter->_last_update);
					ttmp += "\"updated\":\"" + string(buf) + "\",";
					ttmp += "\"id\":\"" + iter->_id + "\",";
					ttmp += "\"command\":\"" + iter->_command + "\"}";

					json.add_array("process",ttmp,true);
					++iter;
				}
			}
			string resp;
			json.serialize(resp);
			session._response.set(Rest::HTTP_BODY,resp);
			return;
		}
		//////////////////////////////////////////////////////////////////////////////////
		//
		//   GET CONFIGURATION DATA FOR OP MODE COMMAND
		//
		//////////////////////////////////////////////////////////////////////////////////
		else if (validate_op_cmd(path, op_path)) {
			//retrieve op node configuration data

			session.vyatta_debug("get op conf data: " + op_path);

			//OK--now that we have the path let's provide the dirt
			TemplateParams params;
			Configuration conf(_debug);

			bool is_admin = false;
			if (session._access_level == Session::k_VYATTACFG) {
				is_admin = true;
			}
			// TODO: op_path needs to be relative
			if (conf.get_operational_node(op_path, params, is_admin) == false) {
				Error(session,Error::COMMAND_NOT_FOUND);
				return;
			}

			//implement json processor here
			//but, for now will piece it together by hand.



			JSON json;
			json.add_value("help",params._help);

			if (params._action == true) {
				string t("true");
				json.add_value("action",t);
			} else {
				string f("false");
				json.add_value("action",f);
			}

			std::vector<NodeParams>::iterator i = params._children_coll.begin();
			while (i != params._children_coll.end()) {
				json.add_array("children",i->_name);
				++i;
			}

			set<string>::iterator j = params._enum.begin();
			while (j != params._enum.end()) {
				string tmp = *j;
				json.add_array("enum",tmp);
				++j;
			}

			string r;
			json.serialize(r);
			session._response.set(Rest::HTTP_BODY,r);
			return;
		}
		//////////////////////////////////////////////////////////////////////////////////
		//
		//   GET MULTIRESPONSE SEGMENT FROM BACKGROUND PROCESS
		//
		//////////////////////////////////////////////////////////////////////////////////
		else {
			//gets background process data
			size_t pos = path.rfind("/");
			session.vyatta_debug("get_bg_data: ");
			if (pos != string::npos) {
				string id = path.substr(pos+1);
				if (id.length() != 16) {
					ERROR(session,Error::VALIDATION_FAILURE);
					return;
				}

				//should look up this id to see if this represents a known process

				session.vyatta_debug(": " + id);

				{
					MultiResponseCommand op_cmd(_debug);
					if (op_cmd.init() == false) {
						ERROR(session,Error::SERVER_ERROR);
						session.vyatta_debug("op:chunker init failed");
						return;
					}
					ProcessData pd = op_cmd.get_process_details(session._user,id);
					if (pd._id == "") {
						//not found, therefore mark as an ended process
						ERROR(session,Error::OPMODE_PROCESS_FINISHED);
						return;
					}
				}

				string out;
				MultiResponseCommand op_cmd(_debug);
				{
					if (op_cmd.init() == false) {
						ERROR(session,Error::SERVER_ERROR);
						session.vyatta_debug("op:chunker init failed");
						return;
					}
					out = op_cmd.get_chunk(session._user,id);
				}
				if (out == "END") {
					//resource is gone!
					MultiResponseCommand kill_cmd(_debug);
					if (kill_cmd.init() == false) {
						ERROR(session,Error::SERVER_ERROR);
						return;
					}
					ERROR(session,Error::OPMODE_PROCESS_FINISHED);
					kill_cmd.kill(session._user,id);
				} else if (out.empty() == true) {
					ERROR(session,Error::ACCEPTED);
				} else {
					session._response.set(Rest::HTTP_RESP_CONTENT_TYPE,"text/plain");
					session._response.set(Rest::HTTP_BODY,out);
					session._response._verbatim_body = true;
					ERROR(session,Error::OK);
				}
			}
		}
		return;
	}
	//////////////////////////////////////////////////////////////////////////////////
	//
	//   DELETE BACKGROUND PROCESS
	//
	//////////////////////////////////////////////////////////////////////////////////
	else if (method == "DELETE") {
		//kills background process
		size_t pos = path.rfind("/");
		string id = path.substr(pos+1);
		if (id.length() < 16) {
			ERROR(session,Error::VALIDATION_FAILURE);
			return;
		}

		MultiResponseCommand op_cmd(_debug);
		if (op_cmd.init() == false) {
			ERROR(session,Error::SERVER_ERROR);
			return;
		}

		op_cmd.kill(session._user,id);
		JSON json;
		string empty(" ");
		json.add_value("message",empty);
		string resp;
		json.serialize(resp);
		session._response.set(Rest::HTTP_BODY,resp);
		return;
	} else {
		//don't recognize method here.
		ERROR(session,Error::VALIDATION_FAILURE);
		return;
	}
}

/**
 * \brief Verify if this a op mode command
 *
 * Uses a side effect of the opd_expand command. If the path is a
 * valid op mode command, opd_expand returns a vector list.
 *
 * \param cmd[in] command from URL
 * \param path[out] relative path for command
 * \return bool Indicates whether the cmd is an op mode command
 **/
bool
OpMode::validate_op_cmd(const std::string &cmd, string &path)
{
	struct opd_connection opd_conn;
	bool result(false);
	struct ::vector *v;
	size_t pfx_len(sizeof("/rest/op/") - 1);

	path = "";

	dsyslog(_debug, "OpMode::%s cmd = %s", __func__, cmd.c_str());
	if (cmd.length() < pfx_len) {
		dsyslog(_debug, "OpMode::%s cmd.length = %zd, pfx_len = %zd", __func__, cmd.length(), pfx_len);
		return false;
	}

	if (opd_open(&opd_conn) == -1) {
		syslog(LOG_ERR, "Unable to connect to opd");
		return false;
	}

	// remove /rest/op/ pfx
	string tmp = cmd.substr(pfx_len);
	v = opd_expand(&opd_conn, tmp.c_str(), NULL);
	if (v) {
		path = tmp;
		result = true;
		vector_free(v);
	}
	opd_close(&opd_conn);
	dsyslog(_debug, "OpMode::%s path = %s", __func__, path.c_str());
	return result;
}


