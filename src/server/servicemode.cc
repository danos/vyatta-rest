/**
 * Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
 * Copyright (c) 2014 by Brocade Communications Systems, Inc.
 * All rights reserved.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 **/

#include <sys/stat.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include "http.hh"
#include "configuration.hh"
#include "rl_str_proc.hh"
#include "servicemode.hh"

using namespace std;

void
ServiceMode::service_index(Session &session)
{
  TemplateParams params;
  Configuration conf;
  bool is_admin = false;

  if (conf.get_operational_node(Rest::SERVICE_COMMAND_DIR, params, is_admin) == false) {
    Error(session, Error::COMMAND_NOT_FOUND);
    return;
  }

  JSON json;
  std::vector<NodeParams>::iterator i = params._children_coll.begin();
  while (i != params._children_coll.end()) {
    TemplateParams tmpl_params;
    if (!conf.get_template_node(Rest::SERVICE_COMMAND_DIR + "/" + i->_name, tmpl_params))
       continue;
    string service = "{\"id\":\"" + i->_name + "\",\"description\":\"" + tmpl_params._help + "\"}";
    json.add_array("services", service, true);
    ++i;
  }

  string r;
  json.serialize(r);
  session._response.set(Rest::HTTP_BODY,r);
  return;
}


void
ServiceMode::execute_service(Session &session, std::string &path)
{
  string command = path.substr(Rest::SERVICE_REQ_ROOT.length());
  if (command.empty()) {
    ERROR(session,Error::VALIDATION_FAILURE);
    return;
  }

  string environment = "export REQUEST_METHOD=" + session._request.get(Rest::HTTP_REQ_METHOD) + ";";
  if (session._session_key.empty() == false) {
    environment += "export SESSION=" + session._session_key + ";";
  }
  if (session._user.empty() == false) {
    environment += "export VYATTA_SESSION_USERNAME=" + session._user + ";";
  }
  environment += "export VYATTA_ACCESS_LEVEL=service-user;";

  string json = session._request.get(Rest::HTTP_BODY);
  FILE *fd = fopen(Rest::JSON_INPUT.c_str(), "w");
  if (!fd) {
    ERROR(session,Error::SERVER_ERROR);
    return;
  }

  if (fwrite(json.c_str(), sizeof(char), json.size(), fd) < json.size()) {
    fclose(fd);
    ERROR(session,Error::SERVER_ERROR);
    return;
  }
  fclose(fd);

  string servicecmd = "/bin/bash -p -c '" + environment + "umask 000; "
                   "source /usr/lib/cgi-bin/vyatta-service;_vyatta_service_run "
                   + command  + " < "+ Rest::JSON_INPUT +"'";

  string cmdout;

  int err = 0;
  if ((err = Mode::system_out(servicecmd.c_str(), cmdout)) != 0) {
    ERROR(session,Error::SERVICEMODE_SCRIPT_ERROR);
  }

  if (!_debug) {
	    unlink(Rest::JSON_INPUT.c_str());
  }

  Mode::handle_cmd_output(cmdout, session);

  if (_debug) {
    FILE *fp = fopen(Rest::JSON_INPUT.c_str(), "a");
    if (fp) {
      fprintf(fp, "XE: '%s'\n", servicecmd.c_str());
      fclose(fp);
    }
  }
}

string
ServiceMode::validate_service_cmd(std::string &cmd)
{
  if (cmd.length() <= string(Rest::SERVICE_REQ_ROOT).length()) {
    return string("");
  }

  // remove /rest/service
  string tmp = cmd.substr(string(Rest::SERVICE_REQ_ROOT).length());

  struct stat s;
  //now construct the relative path for validation
  StrProc str_proc(tmp, "/");
  std::vector<string> coll = str_proc.get();
  std::vector<string>::iterator iter = coll.begin();
  string path = Rest::SERVICE_COMMAND_DIR;
  while (iter != coll.end()) {
    string tmp_path = path + "/" + *iter;
    if (stat(tmp_path.c_str(), &s) != 0) {
      tmp_path = path + "/node.tag";
      if (stat(tmp_path.c_str(), &s) != 0) {
	return string("");
      }
    }
    path = tmp_path;
    ++iter;
  }
  return path;
}


/**
 * \brief Process an servicemode request
 *
 **/
void
ServiceMode::process(Session &session)
{
  if (session._auth_type == Rest::AUTH_TYPE_NONE) {
    ERROR(session,Error::AUTHORIZATION_FAILURE);
    return;
  }

  //now build out command
  string path = session._request.get(Rest::HTTP_REQ_URI);
  if (path.empty()) {
    ERROR(session, Error::VALIDATION_FAILURE);
    return;
  }

  string method = session._request.get(Rest::HTTP_REQ_METHOD);
  if (method == "GET" && path == Rest::SERVICE_REQ_ROOT) {
    service_index(session);
    return;
  }

  if ((method == "GET") && validate_service_cmd(path).empty() == false) {
    execute_service(session, path);
    return;
  }

  ERROR(session,Error::VALIDATION_FAILURE);
  return;
}

