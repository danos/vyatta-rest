/**
 * Module: configuration.cc
 * Description: Configuration support for both op and conf mode.
 *
 * Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
 * Copyright (c) 2009-2013 Vyatta, Inc.
 * All Rights Reserved.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 *
 **/

#include <curl/curl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <signal.h>
#include <syslog.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include <iostream>
#include <fstream>
#include <unistd.h>
#include <string>
#include <dirent.h>
#include <algorithm>
#include <set>
#include <map>
#include <sstream>
#include <algorithm>
#include <iterator>

#include <vyatta-util/map.h>
#include <vyatta-util/vector.h>
#include <client/connect.h>
#include <client/template.h>
#include <client/node.h>
#include <client/auth.h>
#include <client/rpc.h>

#include <opd_client.h>

#include "rl_str_proc.hh"
#include "common.hh"
#include "configuration.hh"
#include "debug.h"

using namespace std;

bool Configuration::_enable_cache(false);
Configuration::CacheColl Configuration::_conf_cache_coll;
Configuration::CacheColl Configuration::_op_cache_coll;

Configuration::Configuration(bool debug) : _conf_id(""), _debug(debug) {
	if (configd_open_connection(&_conn) == -1)
		syslog(LOG_ERR, "webgui: Unable to connect to configuration daemon");
	if (opd_open(&_opd_conn) == -1)
		syslog(LOG_ERR, "webgui: Unable to connect to operational daemon");
}

Configuration::~Configuration() {
	configd_close_connection(&_conn);
	opd_close(&_opd_conn);
}

/**
 * \brief Get configuration session id
 *
 * Private member function
 *
 */
void Configuration::getConvConfId(string &convconfid)
{
	convconfid = _conv_conf_id;
}

/**
 * \brief Set configuration session id
 *
 * Private member function
 *
 * \param conf_id[in] Configuration session id to use
 */
void Configuration::setConfId(const string &conf_id)
{
	_conf_id = conf_id;
	_conv_conf_id = "0x" + _conf_id;
	_conv_conf_id =  Rest::ulltostring(strtoull(_conv_conf_id.c_str(), NULL,0));
	dsyslog(_debug, "Configuration::%s: _conv_conf_id='%s'", __func__, _conv_conf_id.c_str());
	configd_set_session_id(&_conn, _conv_conf_id.c_str());
}

/**
 * \brief Get op-mode node template parameters
 *
 * Operational mode templates can have the following fields:
 * - help
 * - allowed
 * - run
 * - comptype (not supported)
 *
 * \param[in] path Full path to op mode node template
 * \param[out] params Template parameters
 * \return bool TBD
 **/
bool
Configuration::get_op_template_node(const string &path, TemplateParams &params)
{
	size_t pos = 0;
	struct ::map *m;
	struct ::vector *v;
	string cpath(path);

	dsyslog(_debug, "Configuration::%s path='%s'", __func__, path.c_str());

	m = opd_tmpl(&_opd_conn, cpath.c_str(), NULL);
	if (m) {
		const char *next = NULL;
		while ((next = map_next(m, next))) {
			dsyslog(_debug, "Configuration::%s Processing template", __func__);

			string entry(next), key, value;

			// Split entry into key and value
			pos = entry.find("=");
			if (pos == string::npos)
				continue;
			key = entry.substr(0, pos);
			value = entry.substr(pos + 1, entry.length() - pos);

			dsyslog(_debug, "Configuration::%s Processing key='%s', value='%s'",
				__func__, key.c_str(), value.c_str());
			if (key == "help") {
				if (value.find("[REQUIRED]") != string::npos)
					params._mandatory = true;

				// TODO: need to escape out '<' and '>'
				value = Rest::mass_replace(value, "\n", "");
				//need to handle double quotes here
				value = Rest::mass_replace(value, "\"", "'");
				params._help = value;
			} else if (key == "allowed") {
				const char *str = NULL;
				params._allowed_cmd = value;
				cpath += "/";
				v = opd_allowed(&_opd_conn, cpath.c_str(), NULL);
				if (!v)
					dsyslog(_debug, "Configuration::%s Unable to process allowed",
						__func__);
				while ((str = vector_next(v, str)))
					params._enum.insert(str);
				vector_free(v);
			} else if (key == "run") {
				params._action = (value != "");
			} else {
				syslog(LOG_DEBUG, "webgui: Ignoring template key %s", key.c_str());
				continue;
			}
		}
		map_free(m);
	}

	return true;
}


void
split(const std::string &s, char delim, std::vector<std::string> &elems) {
	std::stringstream ss(s);
	std::string item;
	while (std::getline(ss, item, delim)) {
		elems.push_back(item);
	}
	return;
}

/**
 * \brief Get node template parameters
 *
 * Private member function
 *
 * \param[in] path Path to cfg mode template node
 * \param[out] params Template parameters
 * \return bool TBD
 **/
bool
Configuration::get_template_node(const string &path, TemplateParams &params)
{
	bool found_node_dot_def = false;
	size_t pos = 0;
	struct ::map *m;
	string cpath(path);

	// check for existence of template
	if (configd_tmpl_validate_path(&_conn, cpath.c_str(), NULL) != 1)
		return false;

	//if (configd_auth_authorized(&_conn, cpath.c_str(), 2, NULL) != 1) 
	//	return false;

	m = configd_tmpl_get(&_conn, cpath.c_str(), NULL);
	if (m) {
		struct ::vector *v;
		const char *next = NULL;
		bool is_value = false;
		while ((next = map_next(m, next))) {
			// If we have a non-empty map, we have a template
			found_node_dot_def = true;

			string entry(next), key, value;

			// Split entry into key and value
			pos = entry.find("=");
			if (pos == string::npos)
				continue;
			key = entry.substr(0, pos);
			value = entry.substr(pos + 1, entry.length() - pos);
			if (key == "is_value") {
				is_value = true;
			} else if (key == "tag") {
				params._multi = true;
				StrProc str_proc(value,":");
				if (str_proc.get(1).empty() == false) {
					params._multi_limit = strtoul(str_proc.get(1).c_str(),NULL,10);
				}
			} else if (key == "multi") {
				params._multi = true;
				params._end = true;
				StrProc str_proc(value,":");
				if (str_proc.get(1).empty() == false) {
					params._multi_limit = strtoul(str_proc.get(1).c_str(),NULL,10);
				}
			} else if (key == "default") {
				params._default = value;
			} else if (key == "type") {
				// Only handle two types.
				StrProc str_proc(value, ",");
				string e1 = str_proc.get(0);

				if (e1.find("txt") != string::npos) {
					params._type = Rest::TEXT;
				} else if (e1.find("ipv4net") != string::npos) {
					params._type = Rest::IPV4NET;
				} else if (e1.find("ipv4") != string::npos) {
					params._type = Rest::IPV4;
				} else if (e1.find("ipv6net") != string::npos) {
					params._type = Rest::IPV6NET;
				} else if (e1.find("ipv6") != string::npos) {
					params._type = Rest::IPV6;
				} else if (e1.find("u32") != string::npos) {
					params._type = Rest::U32;
				} else if (e1.find("bool") != string::npos) {
					params._type = Rest::BOOL;
				} else if (e1.find("macaddr") != string::npos) {
					params._type = Rest::MACADDR;
				}

				string e2 = str_proc.get(1);
				if (e2.empty() == false) {
					if (e2.find("txt") != string::npos) {
						params._type2 = Rest::TEXT;
					} else if (e2.find("ipv4net") != string::npos) {
						params._type2 = Rest::IPV4NET;
					} else if (e2.find("ipv4") != string::npos) {
						params._type2 = Rest::IPV4;
					} else if (e2.find("ipv6net") != string::npos) {
						params._type2 = Rest::IPV6NET;
					} else if (e2.find("ipv6") != string::npos) {
						params._type2 = Rest::IPV6;
					} else if (e2.find("u32") != string::npos) {
						params._type2 = Rest::U32;
					} else if (e2.find("bool") != string::npos) {
						params._type2 = Rest::BOOL;
					} else if (e2.find("macaddr") != string::npos) {
						params._type2 = Rest::MACADDR;
					}
				}
			} else if (key == "comp_help") {
				// TODO: need to escape out '<' and '>'
				value = Rest::mass_replace(value,"\n","\\n");
				params._comp_help = value;
			} else if (key == "val_help") {
				value = Rest::mass_replace(value, "\t", "\\t");
				std::vector<string> elem;
				split(value, '\n', elem);
				for (std::vector<string>::iterator it = elem.begin(); it != elem.end(); it++) {
					params._val_help.insert(*it);
				}
				//params._val_help.insert(value);
			} else if (key == "help") {
				if (value.find("[REQUIRED]") != string::npos)
					params._mandatory = true;

				// TODO: need to escape out '<' and '>'
				value = Rest::mass_replace(value, "\n", "");
				//need to handle double quotes here
				value = Rest::mass_replace(value, "\"", "'");
				params._help = value;
			} else if (key == "syntax") {
				// TODO: need to escape out '<' and '>'
				string tmp(value);
				StrProc str_proc(tmp, " ");
				if ((str_proc.size() > 3 && str_proc.get(2) == "in")) {
					string meat_str = str_proc.get(3,str_proc.size());

					//now delimit on ","
					StrProc meat_str_proc(meat_str, ",");
					std::vector<string> meat_coll = meat_str_proc.get();
					std::vector<string>::iterator b = meat_coll.begin();
					while (b != meat_coll.end()) {
						bool end = false;
						string tmp = *b;

						//chop off every past the semi-colon
						size_t pos;
						if ((pos = tmp.find(";")) != string::npos) {
							tmp = tmp.substr(0,pos);
							end = true;
						}

						//trim whitespace from both ends
						tmp = Rest::trim_whitespace(tmp);

						//finally strip off quotes if there are any
						if (tmp[0] == '"') {
							size_t p = tmp.find_last_of('"');
							if (p != 0) {
								tmp = tmp.substr(1,p-1);
							}
						}

						if (!tmp.empty()) {
							params._enum.insert(tmp);
						}
						if (end) {
							break;
						}
						++b;
					}
				}
			} else if (key == "enumeration") {
				params._enumeration_cmd = value;
			} else if (key == "allowed") {
				params._allowed_cmd = value;
                        } else if (key == "secret") {
                                params._secret = true;
			} else if (key == "run") {
				//at some point expand this to conf
				//mode to denote a node with an action
				//associated with it.
				params._action = true;
			} else {
				syslog(LOG_DEBUG, "webgui: Ignoring template key %s", key.c_str());
				continue;
			}

			v = configd_tmpl_get_children(&_conn, cpath.c_str(), NULL);
			if (vector_count(v) == 0) {
				//typeless leaf nodes
				params._end = true;
			}
			vector_free(v);
		}
		map_free(m);
		params.node_type = configd_node_get_type(&_conn, cpath.c_str(), NULL);
		if (params.node_type != NODE_TYPE_CONTAINER) {
			const char *str = NULL;
			v = configd_tmpl_get_allowed(&_conn, cpath.c_str(), NULL);
			if (!v)
				dsyslog(_debug, "Configuration::%s Unable to process allowed",
						__func__);
			while ((str = vector_next(v, str))) {
				string tmp = Rest::mass_replace(string(str), "\\<\\>", "*");
				params._enum.insert(tmp);
			}
			vector_free(v);
		}

		/*TODO: Workaround cstore and gui semantic mismatch once we have a system
		  with proper semantics we need to revisit this fix.*/
		if (is_value && params._multi && !params._end) {
			params._type = Rest::NONE;
			params._enum.clear();
			params._val_help.clear();
			params._help = "";
			params._multi = false;
		}
	}

	// Return true to indicate there might be children
	if (found_node_dot_def == false) {
		return true;
	}


	//infer end node for typeless leaf
	if (params._type != Rest::NONE && params._multi == false) {
		params._end = true;
	}

	return true;
}


/**
 * \brief Read operational mode node template
 * public
 *
 * \param[in] node_path Full path to node
 * \param[out] tmpl_params Parsed template parameters of node and children
 * \param[in] is_admin Not used
 * \return bool TBD
 **/
bool
Configuration::get_operational_node(const string &node_path, TemplateParams &tmpl_params, bool is_admin)
{
	// opd uses assumed root paths (i.e., no leading /)
	string cpath(node_path);
	if (cpath[0] == '/')
		cpath.erase(0, 1);

	if (get_op_template_node(cpath, tmpl_params) == false) {
		return false;
	}

	struct ::vector *children = opd_children(&_opd_conn, cpath.c_str(), NULL);
	if (vector_count(children) == 0) {
		//typeless leaf nodes
		tmpl_params._end = true;
	} else {
		const char *child = NULL;
		while ((child = vector_next(children, child))) {
			NodeParams np;
			if (strcmp(child, "node.tag") == 0) {
				np._name = "*";
			} else {
				np._name = child;
			}
			np._state = NodeParams::k_ACTIVE;
			tmpl_params._children_coll.push_back(np);
		}
	}
	vector_free(children);
	return true;
}


/**
 * \brief Get configuration node and parse
 * public
 *
 * \param data_path Path to node
 * \param conf_id Configuration id
 * \param tmpl_params Parsed template parameters (output)
 **/
bool
Configuration::get_configured_node(const string &data_path, const string &conf_id, TemplateParams &tmpl_params)
{
	dsyslog(_debug, "Configuration::%s data_path='%s', conf_id=%s", __func__,
		data_path.c_str(), conf_id.c_str());

	setConfId(conf_id);
	string rel_config_path = data_path;
	if (get_template_node(rel_config_path, tmpl_params) == false) {
		return false;
	}

	// Populate children in tmpl_params
	parse_value_and_state(rel_config_path, conf_id, tmpl_params);

	// Set template disable state and mirror in all children
	tmpl_params._data._disabled_state = NodeParams::k_ENABLE;

	std::vector<NodeParams>::iterator i = tmpl_params._children_coll.begin();
	while (i != tmpl_params._children_coll.end()) {
		if (tmpl_params._data._disabled_state != NodeParams::k_ENABLE) {
			i->_disabled_state = tmpl_params._data._disabled_state;
		} else {
			i->_disabled_state = NodeParams::k_ENABLE;
		}
		++i;
	}

	return true;
}

/*
 * \brief Based on the status of the node, set the node parameters
 *
 * \param cpath[in]
 * \param node[out]
 */
void Configuration::get_node_params(const string &cpath, NodeParams &node)
{
	// Set name as last element of cpath
	size_t pos = cpath.rfind("/", std::string::npos);
	if (pos != std::string::npos) {
		node._name = cpath.substr(pos+1, std::string::npos);
	} else {
		node._name = cpath;
	}
	dsyslog(_debug, "Configuration::%s: Setting node name = %s  path = %s", __func__, node._name.c_str(), cpath.c_str());
	switch (configd_node_get_status(&_conn, CANDIDATE, cpath.c_str(), NULL)) {
	case NODE_STATUS_DELETED:
		node._state = NodeParams::k_DELETE;
		node._is_changed = "true";
		break;
	case NODE_STATUS_CHANGED:
		node._state = NodeParams::k_ACTIVE;
		node._is_changed = "true";
		break;
	case NODE_STATUS_ADDED:
		node._state = NodeParams::k_SET;
		node._is_changed = "true";
		break;
	case NODE_STATUS_UNCHANGED:
		if (configd_node_exists(&_conn, RUNNING, cpath.c_str(), NULL)) {
			node._state = NodeParams::k_ACTIVE;
		} else {
			node._state = NodeParams::k_NONE;
		}
		node._is_changed = "false";
		break;
	default: // error
		node._state = NodeParams::k_NONE;
		node._is_changed = "false";
		break;
	}
}

/*
 * \brief Escape special characters, like /
 *
 * \param in[in] string to be escaped 
 * \return string escaped string
 */
string
url_escape(string in) {
	string out = "";
	CURL *c = curl_easy_init();
	char *rets = curl_easy_escape(c, in.c_str(), in.length());
	if (rets != NULL) { 
		out = string(rets);
	}
	curl_free(rets);
	curl_easy_cleanup(c);
	return out;
}

/**
 * \brief Parse configuration node template
 * Private member function
 *
 * \param rel_data_path[in] Relative path to ro active configuration
 * \param conf_id[in] Configuration id
 * \param params[in,out] Parsed template parameters
 **/
void
Configuration::parse_value_and_state(const string &rel_data_path, const string &conf_id, TemplateParams &params)
{
	NodeParams np;
	string cpath(rel_data_path);
	string child;
	string child_cpath;

	dsyslog(_debug, "Configuration::%s rel_data_path='%s', conf_id=%s", __func__,
		rel_data_path.c_str(), conf_id.c_str());

	get_node_params(cpath, params._data);

	// Iterate over the children and populate the children nodes here.
	std::map<string,NodeParams::CONF_STATE> state_coll;
	std::vector<string> value_coll;
	struct ::vector *children;

	switch (params.node_type) {
	case NODE_TYPE_LEAF:
	case NODE_TYPE_MULTI:
	case NODE_TYPE_TAG:
		children = configd_node_get(&_conn, RUNNING, cpath.c_str(), NULL);
		for (const char *next = NULL; (next = vector_next(children, next)); ) {
			child = next;
			child_cpath.clear();
			if (!cpath.empty()) {
				child_cpath = cpath + "/";
			}
			child_cpath += url_escape(child);

			get_node_params(child_cpath, np);
			value_coll.push_back(child);
			state_coll.insert(pair<string,NodeParams::CONF_STATE>(child, np._state));
		}
		vector_free(children);

		children = configd_node_get(&_conn, CANDIDATE, cpath.c_str(), NULL);
		for (const char *next = NULL; (next = vector_next(children, next)); ) {
			child = next;

			if (state_coll.find(child) != state_coll.end())
				continue;

			child_cpath.clear();
			if (!cpath.empty()) {
				child_cpath = cpath + "/";
			}
			child_cpath += url_escape(child);

			get_node_params(child_cpath, np);
			value_coll.push_back(child);
			state_coll.insert(pair<string,NodeParams::CONF_STATE>(child, np._state));
		}
		vector_free(children);
		break;
	case NODE_TYPE_CONTAINER:
		children = configd_tmpl_get_children(&_conn, cpath.c_str(), NULL);
		for (const char *next = NULL; (next = vector_next(children, next)); ) {
			child = next;
			child_cpath.clear();
			if (!cpath.empty()) {
				child_cpath = cpath + "/";
			}
			child_cpath += child;

			NodeParams::CONF_STATE state = NodeParams::k_NONE;
			if (configd_node_exists(&_conn, CANDIDATE, child_cpath.c_str(), NULL) == 1)
				state = NodeParams::k_SET;

			if (configd_node_exists(&_conn, RUNNING, child_cpath.c_str(), NULL) == 1) {
				if (state != NodeParams::k_SET)
					state = NodeParams::k_DELETE;
				else
					state = NodeParams::k_ACTIVE;
			}
			value_coll.push_back(child);
			state_coll.insert(pair<string,NodeParams::CONF_STATE>(child, state));
		}
		vector_free(children);
		break;
	default: // error
		dsyslog(_debug, "Configuration::%s: Unable to get node type, '%s'", __func__,
			cpath.c_str());
		break;
	}

	// now that we've figured out the collection, lets populate the children
	std::vector<string>::iterator i = value_coll.begin();
	while (i != value_coll.end()) {
		dsyslog(_debug, "Configuration::%s: Checking child '%s'", __func__, i->c_str());
		std::map<string,NodeParams::CONF_STATE>::iterator j = state_coll.find(*i);
		if (j != state_coll.end()) { //should always be found...
			np._name = j->first;
			np._state = j->second;
			dsyslog(_debug, "Configuration::%s: Adding child '%s' with state %d", __func__,
				np._name.c_str(), np._state);
			params._children_coll.push_back(np);
		}
		++i;
	}
}

