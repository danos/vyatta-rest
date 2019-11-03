/**
 * Module: confmode.cc
 * Description: Configuration mode support implementation.
 *
 * Copyright (c) 2017-2019, AT&T Intellectual Property.  All rights reserved.
 * Copyright (c) 2009-2013 Vyatta, Inc.
 * All Rights Reserved.
 *
 * SPDX-License-Identifier: GPL-2.0-only

 **/

#include <cstdio>
#include <sys/types.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <unistd.h>
#include <syslog.h>
#include <string>
#include <string.h>
#include <dirent.h>
#include <curl/curl.h>

#include <client/connect.h>
#include <client/session.h>
#include <client/transaction.h>
#include <client/error.h>

#include "rl_str_proc.hh"
#include "common.hh"
#include "http.hh"
#include "mode.hh"
#include "configuration.hh"
#include "confmode.hh"
#include "debug.h"

using namespace std;


const std::string ConfMode::_shell_env = "export VYATTA_TEMPLATE_LEVEL=/;\
export VYATTA_MOD_NAME=.modified;\
export vyatta_datadir=/opt/vyatta/share;\
export vyatta_sysconfdir=/opt/vyatta/etc;\
export vyatta_sharedstatedir=/opt/vyatta/com;\
export VYATTA_TAG_NAME=node.tag;\
export vyatta_sbindir=/opt/vyatta/sbin;\
export VYATTA_CFG_GROUP_NAME=vyattacfg;\
export vyatta_bindir=/opt/vyatta/bin;\
export vyatta_libdir=/opt/vyatta/lib;\
export VYATTA_EDIT_LEVEL=/;\
export vyatta_libexecdir=/opt/vyatta/libexec;\
export vyatta_localstatedir=/opt/vyatta/var;\
export vyatta_prefix=/opt/vyatta;\
export vyatta_datarootdir=/opt/vyatta/share;\
export vyatta_configdir=/opt/vyatta/config;\
export UNIONFS=unionfs;\
export vyatta_infodir=/opt/vyatta/share/info;\
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin;\
export COMMIT_VIA=gui2_rest;\
export VYATTA_OUTPUT_ERROR_LOCATION=TRUE;\
export vyatta_localedir=/opt/vyatta/share/locale;";



ConfMode::ConfMode(bool debug) : Mode(debug)
{
	_curl_handle = curl_easy_init();
}

ConfMode::~ConfMode()
{
	curl_easy_cleanup(_curl_handle);
}
string ConfMode::conv_url(string tmp)
{
	int len;
	char *decode = curl_easy_unescape(_curl_handle, tmp.c_str(),
			tmp.length(), &len);
	tmp = string(decode);
	curl_free(decode);
	return tmp;
}
/**
 * \brief Process an HTTP session
 * \param session Session to process
 **/
void
ConfMode::process(Session &session)
{
	if (session._auth_type == Rest::AUTH_TYPE_NONE) {
		ERROR(session,Error::AUTHORIZATION_FAILURE);
		return;
	}

	session.vyatta_debug("CONF:A");

	//request body contains key, value pairs that need to be passed down as json
	string path = session._request.get(Rest::HTTP_REQ_URI);
	if (path.empty()) {
		session.vyatta_debug("conf:1");
		ERROR(session,Error::VALIDATION_FAILURE);
		return;
	}

	if (path.length() < Rest::CONF_REQ_ROOT.length()) {
		ERROR(session,Error::VALIDATION_FAILURE);
		return;
	}

	string method = session._request.get(Rest::HTTP_REQ_METHOD);
	if (method.empty()) {
		ERROR(session,Error::VALIDATION_FAILURE);
		return;
	}

	session.vyatta_debug("CONF:B");

	//does this user have cfg level access?
	if (session._access_level != Session::k_VYATTACFG) {
		//    session._response.set(Rest::HTTP_RESP_WWWAUTH,"Basic realm=\"Secure Area\"");
		ERROR(session,Error::AUTHORIZATION_FAILURE);
		return;
	}

	string conf_path_with_id, id, tag;
	string user = session._user;
	if (path.length() > Rest::CONF_REQ_ROOT.length()) {
		conf_path_with_id = path.substr(string(Rest::CONF_REQ_ROOT).length());
		//need to require id in the request first.
		size_t pos = conf_path_with_id.substr(1).find("/");
		id = conf_path_with_id.substr(1,pos);

		//if this is a tag instead of an id, let's look it up...
		if (Rest::read_conf_modify_file(id,user,tag) == false) {
			tag = id;
			if (method != "POST" && Rest::read_conf_modify_file_from_tag(tag,user,id) == false) { //well then lookup by tag
				ERROR(session,Error::VALIDATION_FAILURE);
				return;
			}
		}
	}

	//If this is a request with id then make sure this is the users id


	//////////////////////////////////////////////////////////////////////////////////
	//
	//   GET CONFIGURATION MODE DATA
	//
	//////////////////////////////////////////////////////////////////////////////////
	if (method == "GET") {
		//////////////////////////////////////////////////////////////////////////////////
		//
		//   GET LIST OF ACTIVE CONFIGURATIONS
		//
		//////////////////////////////////////////////////////////////////////////////////
		if (path == Rest::CONF_REQ_ROOT) {

			//look at configuration listings on dir, filter by user
			struct dirent *dirp;
			DIR *dp;
			if ((dp = opendir(Rest::CONFIG_TMP_DIR.c_str())) == NULL) {
				ERROR(session,Error::SERVER_ERROR);
				return;
			}

			JSON json_root;
			string empty(" ");
			json_root.add_value("message",empty);
			if (dp != NULL) {
				while ((dirp = readdir(dp)) != NULL) {
					string conf_file = string(dirp->d_name);
					if (conf_file.length() < 22) {
						continue;
					}

					string id = string(dirp->d_name).substr(14);
					if (strncmp(dirp->d_name,".vyattamodify_",14) == 0) {
						struct stat s;
						string started = "0";
						string updated = "0";
						string tmp_path = Rest::CONFIG_TMP_DIR + string(dirp->d_name);

						string conf_user;
						string description;
						if (Rest::read_conf_modify_file(id, conf_user, description) == false) {
							continue;
						}

						if (conf_user != session._user) {
							continue; //not yours man...
						}

						if (stat(tmp_path.c_str(), &s) == 0) {
							time_t t = s.st_mtime;
							char buf[80];
							sprintf(buf,"%ld",(unsigned long)t);
							started = string(buf);
							t = s.st_ctime;
							sprintf(buf,"%ld",(unsigned long)t);
							updated = string(buf);
						}

						//let's add test for uncommitted changes
						string convconfid = "0x"+id;
						convconfid = Rest::ulltostring(strtoull(convconfid.c_str(), NULL,0));
						string mods = is_configd_sess_changed(convconfid) ? "true" : "false";

						//TODO: NEED TO FILTER ON USER
						//TODO: FIX json object to handle arrays of hashes
						string ttmp = "{\"id\":\""+id+"\",";
						ttmp += "\"username\":\""+session._user+"\",";
						ttmp += "\"description\":\""+description+"\",";
						ttmp += "\"started\":\""+started+"\",";
						ttmp += "\"modified\":\""+mods+"\",";
						ttmp += "\"updated\":\""+updated+"\"}";
						json_root.add_array("session",ttmp,true);
					}
				}

				string resp;
				json_root.serialize(resp);
				session._response.set(Rest::HTTP_BODY,resp);
				closedir(dp);
			}
		}
		//////////////////////////////////////////////////////////////////////////////////
		//
		//   GET CONFIGURATION MODE DATA
		//
		//////////////////////////////////////////////////////////////////////////////////
		else {
			TemplateParams params;

			//does the user own this configuration session?
			string conf_user = user;
			string description = tag;
			if (conf_user != session._user) {
				ERROR(session,Error::VALIDATION_FAILURE);
				return;
			}

			size_t pos = conf_path_with_id.substr(1).find("/");
			string conf_path_url_encoded = conf_path_with_id.substr(pos+2);
			// Convert from / sep path to space sep cpath
			if (conf_path_url_encoded[0] == ' ') {
				conf_path_url_encoded.erase(0, 1);
			}

			Configuration conf(_debug);
			if (conf.get_configured_node(conf_path_url_encoded, id, params) == false) {
				Error(session,Error::COMMAND_NOT_FOUND);
				return;
			}

			JSON json;
			json.add_value("help",params._help);

			//type
			string bar = Rest::g_type_str[params._type];
			json.add_array("type",bar);

			//type
			bar = Rest::g_type_str[params._type2];
			if (bar != "none") {
				json.add_array("type",bar);
			}

			if (params._default != "\n") {
				json.add_value("default",params._default);
			}


			string tmp = params._comp_help;
			tmp = Rest::mass_replace(tmp,"\"","\\\"");
			char *encode = curl_easy_escape(_curl_handle, tmp.c_str(), tmp.length());
			tmp = string(encode);
			curl_free(encode);
			json.add_value("comp_help", tmp);

			if (params._val_help.empty() == false) {
				set<string>::iterator iter = params._val_help.begin();
				while (iter != params._val_help.end()) {
					string l = *iter;
					if (l.empty() == false) {
						//find ;, then find :
						size_t pos1 = l.find(";");
						if (pos1 != string::npos) {
							string val = " ",type;
							string help = l.substr(pos1+2,l.length()-3);
							help = Rest::mass_replace(help,"\"","\\\"");
							help = Rest::mass_replace(help,"\n","");
							string desc = l.substr(0,pos1);
							size_t pos2 = desc.find(":");
							if (pos2 != string::npos) {
								type = desc.substr(0,pos2);
								val = desc.substr(pos2+1,desc.length()-2);
							} else {
								type = desc;
							}
							string tmp = "{\"type\":\""+type+"\",\"vals\":\""+val+"\",\"help\":\""+help+"\"}";
							json.add_array("val_help",tmp, true);
						}

					}
					++iter;
				}
			}

			json.add_value("allowed",params._allowed);
			string foo("true");
			if (params._multi == true) {
				json.add_value("multi",foo);
			}
			if (params._multi_limit > 0) {
				char buf[512];
				sprintf(buf,"%ld",params._multi_limit);
				string tmp(buf);
				json.add_value("multi_limit",tmp);
			}
			if (params._end == true) {
				json.add_value("end",foo);
			}
			if (params._action == true) {
				json.add_value("action",foo);
			}
			if (params._mandatory == true) {
				json.add_value("mandatory",foo);
			}
                        if (params._secret == true) {
                                json.add_value("secret",foo);
                        }

			json.add_value("name",params._data._name);
			string state = "none";
			if (params._data._state == NodeParams::k_SET) {
				state = "set";
			} else if (params._data._state == NodeParams::k_DELETE) {
				state = "delete";
			} else if (params._data._state == NodeParams::k_ACTIVE) {
				state = "active";
			}
			json.add_value("state",state);
			json.add_value("is_changed", params._data._is_changed);

			string disable_state = "enable";
			if (params._data._disabled_state == NodeParams::k_DISABLE) {
				disable_state = "disable";
			} else if (params._data._disabled_state == NodeParams::k_DISABLE_LOCAL) {
				disable_state = "disable-local";
			} else if (params._data._disabled_state == NodeParams::k_ENABLE_LOCAL) {
				disable_state = "enable-local";
			}
			json.add_value("deactivate_state",disable_state);

			std::vector<NodeParams>::iterator ii = params._children_coll.begin();
			while (ii != params._children_coll.end()) {
				string state = "none";
				if (ii->_state == NodeParams::k_SET) {
					state = "set";
				} else if (ii->_state == NodeParams::k_ACTIVE) {
					state = "active";
				} else if (ii->_state == NodeParams::k_DELETE) {
					state = "delete";
				}

				string disable_state = "enable";
				if (ii->_disabled_state == NodeParams::k_DISABLE) {
					disable_state = "disable";
				} else if (ii->_disabled_state == NodeParams::k_DISABLE_LOCAL) {
					disable_state = "disable-local";
				} else if (ii->_disabled_state == NodeParams::k_ENABLE_LOCAL) {
					disable_state = "enable-local";
				}

				string tmp = "{\"name\":\""+ii->_name+"\",\"state\":\""+state+"\",\"deactivate_state\":\""+disable_state +"\"}";
				json.add_array("children",tmp, true);
				++ii;
			}

			set<string>::iterator j = params._enum.begin();
			while (j != params._enum.end()) {
				if (j->empty() == false) {
					if (j->find("\"") != string::npos) {
						string t = *j;
						json.add_array("enum",t,true);
					} else {
						string t = *j;
						json.add_array("enum",t,false);
					}
				}
				++j;
			}

			string resp;
			json.serialize(resp);
			session._response.set(Rest::HTTP_BODY,resp);
		}
	}
	//////////////////////////////////////////////////////////////////////////////////
	//
	//   SET CONFIGURATION MODE DATA
	//
	//////////////////////////////////////////////////////////////////////////////////
	else if (method == "PUT") {

		//does the user own this configuration session?
		string conf_user = user;
		string description = tag;
		if (conf_user != session._user) {
			ERROR(session,Error::AUTHORIZATION_FAILURE);
			return;
		}

		if (conf_path_with_id.empty()) {
			ERROR(session,Error::VALIDATION_FAILURE);
			return;
		}

		size_t pos = conf_path_with_id.substr(1).find("/");
		if (pos == string::npos) {
			ERROR(session,Error::VALIDATION_FAILURE);
			return;
		}

		if (conf_path_with_id.length() < 2) {
			ERROR(session,Error::VALIDATION_FAILURE);
			return;
		}

		string conf_path = conf_path_with_id.substr(pos+2);

		string convconfid = "0x"+id;
		convconfid = Rest::ulltostring(strtoull(convconfid.c_str(), NULL,0));
		string command = ConfMode::_shell_env +
		                 "export VYATTA_ACTIVE_CONFIGURATION_DIR=/active;"
		                 + "export VYATTA_CONFIG_TMP=/session/"
		                 + convconfid + Rest::CONFIG_TMP_DIR + ";"
		                 + "export VYATTA_CHANGES_ONLY_DIR=/session/"
		                 + convconfid + Rest::LOCAL_CHANGES_ONLY + ";"
		                 + "export vyatta_cfg_templates=" + Rest::CONF_COMMAND_DIR + ";"
		                 + "export VYATTA_CONFIG_TEMPLATE=" + Rest::CONF_COMMAND_DIR + ";"
		                 + "export VYATTA_TEMP_CONFIG_DIR=/session/"
		                 + convconfid + Rest::LOCAL_CONFIG_DIR + ";"
				 + "export VYATTA_CONFIG_SID=" + convconfid;

		//    session._response.append(Rest::HTTP_RESP_DEBUG,"CONFPATH!:"+conf_path);

		string cmd = Rest::translate_rest_to_cli(_curl_handle,conf_path);

		//    session._response.append(Rest::HTTP_RESP_DEBUG,"CMD!:"+cmd);

		//as a security precaution, lop off everything past the ";"
		//Note: location of bug 6743--need to take into account quotes on the values before lopping off here

		pos = cmd.find(";");
		if (pos != string::npos) {
			if (strncmp(cmd.c_str(),"set",3) != 0 &&
			        strncmp(cmd.c_str(),"delete",6) != 0 &&
			        strncmp(cmd.c_str(),"comment",7) != 0) {
				//lop off when not a set, delete or comment
				//note nodes are single quoted from above
				cmd = cmd.substr(0,pos);
			}
		}

		if (strncmp(cmd.c_str(),"set",3) == 0 ||
		        strncmp(cmd.c_str(),"delete",6) == 0 ||
		        strncmp(cmd.c_str(),"comment",7) == 0) {
			cmd = "/usr/bin/cfgcli -print " + cmd;
		} else if (strncmp(cmd.c_str(),"activate",8) == 0 || strncmp(cmd.c_str(),"deactivate",10) == 0) {
			cmd = "/opt/vyatta/sbin/vyatta-activate-config.pl " + cmd;
		} else {
			if (_debug) {
				JSON json;
				json.add_value("cmd",cmd);
				string resp;
				json.serialize(resp);
				session._response.set(Rest::HTTP_BODY,resp);
			}
			ERROR(session,Error::COMMAND_NOT_FOUND);
			return;
		}
		command += ";" + cmd + " 2>&1";
		string stdout;


		//NOTE error codes are not currently being returned via the popen call--temp fix until later investigation
		if (Rest::execute(command,stdout,true) != 0) {
			stdout = Rest::mass_replace(stdout,"\"","\\\"");
			stdout = Rest::mass_replace(stdout,"\n","\\n");
			ERROR(session,Error::CONFIGURATION_ERROR,stdout);
		}
	}
	//////////////////////////////////////////////////////////////////////////////////
	//
	//   DELETE CONFIGURATION MODE DATA
	//
	//////////////////////////////////////////////////////////////////////////////////
	else if (method == "DELETE") {
		//clear out the session

		//does the user own this configuration session?
		string conf_user = user;
		string description = tag;
		if (conf_user != session._user) {
			ERROR(session,Error::VALIDATION_FAILURE);
			return;
		}


		discard_session(id,true);

		JSON json;
		string empty(" ");
		json.add_value("message",empty);
		string resp;
		json.serialize(resp);
		session._response.set(Rest::HTTP_BODY,resp);

		if (_debug) {
			session._response.set(Rest::HTTP_BODY,"delete configuration mode data");
		}
	} else if (method == "POST") {
		//////////////////////////////////////////////////////////////////////////////////
		//
		//   CREATE NEW CONFIGURATION
		//
		//////////////////////////////////////////////////////////////////////////////////
		session.vyatta_debug("CONF:C");

		//looks for an additional slash then consider this an action, allows for room for description field
		if (conf_path_with_id == "" || conf_path_with_id.substr(1).find("/") == string::npos) {
			session.vyatta_debug("CONF:D");

			string description;
			if (conf_path_with_id != "") {
				description = conf_path_with_id.substr(1);
			}

			//verify description is unique for this user if defined
			string id;
			if (description.empty() == false && Rest::read_conf_modify_file_from_tag(description,user,id) == true) {
				//already specified by this user, therefore rejecting new use
				ERROR(session,Error::CONFMODE_DUP_DESC_ERROR);
				return;
			}

			id = Rest::generate_token();
			if (id.length() < 16) {
				ERROR(session,Error::VALIDATION_FAILURE);
				return;
			}
			string convconfid = "0x"+id;
			convconfid = Rest::ulltostring(strtoull(convconfid.c_str(), NULL,0));

			if (!setup_session(convconfid))
				dsyslog(_debug, "ConfMode::%s: setup_session failed", __func__);

			//write the username here to modify file
			if (Rest::create_conf_modify_file(id,session._user,description) == false) {
				ERROR(session,Error::SERVER_ERROR);
				return;
			}

			string location = string("rest/conf/")+id;
			session._response.set(Rest::HTTP_RESP_LOCATION,location);
			ERROR(session,Error::CREATED);
		}
		//////////////////////////////////////////////////////////////////////////////////
		//
		//   ISSUE CONFIGURATION MODE COMMAND
		//
		//////////////////////////////////////////////////////////////////////////////////
		else {

			//check that tag can be found...
			if (tag == id && Rest::read_conf_modify_file_from_tag(tag,user,id) == false) { //well then lookup by tag
				ERROR(session,Error::VALIDATION_FAILURE);
				return;
			}

			//does the user own this configuration session?
			string conf_user = user;
			string description = tag;
			if (conf_user != session._user) {
				ERROR(session,Error::AUTHORIZATION_FAILURE);
				return;
			}

			size_t pos = conf_path_with_id.substr(1).find("/");
			string cmd_path = conf_path_with_id.substr(pos+2);

			string convconfid = "0x"+id;
			convconfid = Rest::ulltostring(strtoull(convconfid.c_str(), NULL,0));
			string command = ConfMode::_shell_env +
			                 "export VYATTA_ACTIVE_CONFIGURATION_DIR=/active;"
			                 + "export VYATTA_CONFIG_TMP=/session/"
			                 + convconfid + Rest::CONFIG_TMP_DIR + ";"
			                 + "export VYATTA_CHANGES_ONLY_DIR=/session/"
			                 + convconfid + Rest::LOCAL_CHANGES_ONLY + ";"
			                 + "export vyatta_cfg_templates=" + Rest::CONF_COMMAND_DIR + ";"
			                 + "export VYATTA_CONFIG_TEMPLATE=" + Rest::CONF_COMMAND_DIR + ";"
			                 + "export VYATTA_TEMP_CONFIG_DIR=/session/"
			                 + convconfid + Rest::LOCAL_CONFIG_DIR + ";"
					 + "export VYATTA_CONFIG_SID=" + convconfid;

			string tmp;
			string cmd = cmd_path;
			string action = cmd_path;
			session.vyatta_debug("CONF:G");

			if ((action == "commit") || (action == "save")  ||
					(action == "save/config.boot")) {
				string stdout = "";
				struct configd_conn conn;
				if (configd_open_connection(&conn) == -1) {
					dsyslog(_debug, "ConfMode::%s: Unable to open connection", __func__);
					return;
				}
				configd_set_session_id(&conn, convconfid.c_str());
				struct configd_error err;
				char * buf;
				if (action == "commit")
					buf = configd_commit(&conn, "via gui", &err);
				else
					buf = configd_save(&conn, NULL, &err);
				if (buf == NULL) {
					if (err.text != NULL) {
						buf = err.text;	
					}
					ERROR(session,Error::CONFIGURATION_ERROR);
				}
				stdout = string(buf);
				if ((stdout == "") && (action != "commit")) {
					stdout = "Saving configuration to '/config/config.boot'... Done";
				}
				stdout = Rest::mass_replace(stdout,"\"","\\\"");
				stdout = Rest::mass_replace(stdout,"\n","\\n");

				JSON json;
				json.add_value("message",stdout);
				if (_debug) {
					json.add_value("command",command);
				}
				string resp;
				json.serialize(resp);
				session._response.set(Rest::HTTP_BODY,resp);
				configd_close_connection(&conn);
				return;
			} else if (action == "discard") {
				discard_session(id,false);
				return;
			} else if (action.length() > 4 && action.substr(0,4) == "save") {
				tmp = "umask 0002 ; /opt/vyatta/sbin/vyatta-save-config.pl";
				string tmp2 = action.substr(5,action.length()-5);
				tmp2 = Rest::mass_replace(tmp2,"/"," ");
				tmp += string(" '") + tmp2 + "'" + " --no-defaults";
				tmp = conv_url(tmp);
			} else if (action.length() > 4 && action.substr(0,5) == "merge") {
				tmp = "/opt/vyatta/sbin/vyatta-load-config.pl --merge";
				//grab filename is present
				if (action.length() > 5) {
					string tmp2 = action.substr(6,action.length()-6);
					tmp2 = Rest::mass_replace(tmp2,"/"," ");
					tmp += string(" '") + tmp2 + "'";
					tmp = conv_url(tmp);
				}
			} else if (action.length() > 3 && action.substr(0,4) == "load") {
				tmp = "/opt/vyatta/sbin/vyatta-load-config.pl";
				//grab filename is present
				if (action.length() > 4) {
					string tmp2 = action.substr(5,action.length()-5);
					tmp2 = Rest::mass_replace(tmp2,"/"," ");
					tmp += string(" '") + tmp2 + "'";
					tmp = conv_url(tmp);
				}
			} else if (action.length() > 7 && action.substr(0,8) == "show-all") {
				if (action.length() == 8) {
					tmp = "/bin/cli-shell-api showConfig --show-show-defaults";
				} else {
					string tmp2 = action.substr(9,action.length()-9);
					tmp2 = Rest::mass_replace(tmp2,"/"," ");
					tmp = "/bin/cli-shell-api showConfig --show-show-defaults '" + tmp2 + "'";
				}
			} else if (action.length() > 3 && action.substr(0,4) == "show") {
				if (action.length() == 4) {
					tmp = "/bin/cli-shell-api showConfig";
				} else {
					string tmp2 = action.substr(5,action.length()-5);
					tmp2 = Rest::mass_replace(tmp2,"/"," ");
					tmp = "/bin/cli-shell-api showConfig '" + tmp2 + "'";
				}
			} else {
				ERROR(session,Error::VALIDATION_FAILURE);
				return;
			}

			session.vyatta_debug("CONF:H");
			command += ";" + tmp;
			command += " 2>&1";

			string stdout = " ";
			if (Rest::execute(command,stdout,true) != 0) {
				if (_debug) {
					JSON json;
					json.add_value("cmd",command);
					string resp;
					json.serialize(resp);
					session._response.set(Rest::HTTP_BODY,resp);
				}
				ERROR(session,Error::CONFIGURATION_ERROR);
				//	return;
			}

			// escape backslash
			stdout = Rest::mass_replace(stdout, "\\", "\\\\");
			//escape quote
			stdout = Rest::mass_replace(stdout,"\"","\\\"");
			// cr, lf and tab
			stdout = Rest::mass_replace(stdout, "\r", "\\r");
			stdout = Rest::mass_replace(stdout,"\n","\\n");
			stdout = Rest::mass_replace(stdout,"\t","\\t");

			JSON json;
			json.add_value("message",stdout);
			if (_debug) {
				json.add_value("command",command);
			}
			string resp;
			json.serialize(resp);
			session._response.set(Rest::HTTP_BODY,resp);
		}
	} else {
		//don't recognize method here.
		ERROR(session,Error::VALIDATION_FAILURE);
	}

	return;
}


/**
 * \brief Setup config session
 *
 * \param sid[in] Converted configuration session id
 **/
bool ConfMode::setup_session(const string &sid)
{
	struct configd_conn conn;
	bool result;

	if (configd_open_connection(&conn) == -1) {
		dsyslog(_debug, "ConfMode::%s: Unable to open connection", __func__);
		return false;
	}

	configd_set_session_id(&conn, sid.c_str());
	result = (configd_sess_setup(&conn, NULL) != -1);
	dsyslog(_debug, "ConfMode::%s: result = %d", __func__, result);

	configd_close_connection(&conn);
	return result;
}


/**
 * \brief Discard config session
 *
 * \param id[in] Configuration session id
 * \param exit_session[in] Flag to also teardown the session
 **/
void
ConfMode::discard_session(string &id, bool exit_session)
{
	if (id.empty()) {
		return;
	}
	string convconfid = "0x"+id;
	convconfid = Rest::ulltostring(strtoull(convconfid.c_str(), NULL,0));

	struct configd_conn conn;
	if (configd_open_connection(&conn) == -1) {
		dsyslog(_debug, "ConfMode::%s: Unable to open connection", __func__);
		return;
	}

	dsyslog(_debug, "ConfMode::%s: Setting session id = %s", __func__, convconfid.c_str());
	configd_set_session_id(&conn, convconfid.c_str());
	configd_discard(&conn, NULL);
	if (exit_session)
		configd_sess_teardown(&conn, NULL);
	configd_close_connection(&conn);

	string mod_file = Rest::VYATTA_MODIFY_FILE + id;
	if (exit_session == true) {
		unlink(mod_file.c_str());
	}

}


/**
 * \brief Determine if session changed
 *
 * \param sid[in] Converted configuration session id
 * \return bool Whether the config session has changed
 **/
bool ConfMode::is_configd_sess_changed(const string &sid)
{
	struct configd_conn conn;
	bool result;

	if (configd_open_connection(&conn) == -1) {
		dsyslog(_debug, "ConfMode::%s: Unable to open connection", __func__);
		return false;
	}

	configd_set_session_id(&conn, sid.c_str());
	result = (configd_sess_changed(&conn, NULL) == 1);

	configd_close_connection(&conn);
	return result;
}
