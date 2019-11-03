/**
 * Module: configuration.hh
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2009, 2010 Vyatta, Inc.
 * All Rights Reserved.
 * Authors: Michael Larson
 * Date: 2010
 * Description: configuration mode definitions
 *
 **/

#ifndef __CONFIGURATION_HH__
#define __CONFIGURATION_HH__

#include <set>
#include <map>
#include <string>
#include <vector>
#include "common.hh"

#include <client/connect.h>
#include <opd_client.h>

/**
 *
 *
 **/
class NodeParams
{
public:
	typedef enum {
		k_NONE,		///< Node not present in configuration
		k_ACTIVE,	///< Node present in configuration
		k_SET,		///< Node added to configuration
		k_DELETE	///< Node deleted from configuration
	} CONF_STATE;
	typedef enum {k_ENABLE,k_ENABLE_LOCAL,k_DISABLE,k_DISABLE_LOCAL} DISABLE_STATE;
public:
	NodeParams() : _state(k_NONE),_disabled_state(k_ENABLE) {}

	std::string _name; ///< also represents values too
	CONF_STATE _state;
	std::string _is_changed;
	DISABLE_STATE _disabled_state;
};

/**
 *
 *
 **/
class TemplateParams
{
public:

public:
	TemplateParams() :
		_multi(false),
		_multi_limit(0),
		_end(false),
		_action(false),
		_type(Rest::NONE),
		_type2(Rest::NONE),
		_conf_mode(Rest::NOATTR),
		_mandatory(false),
                _secret(false) {}
	bool _multi;
	unsigned long _multi_limit;
	bool _end;
	bool _action;
	Rest::NodeType _type;
	Rest::NodeType _type2;
	Rest::Attributes _conf_mode;
	std::string _help;
	std::string _comp_help;
	std::set<std::string> _val_help;
	bool        _mandatory;
        bool        _secret;
	std::string _default;
	std::set<std::string> _enum;
	std::string _enumeration_cmd; ///< used for caching purposes
	std::string _allowed_cmd; ///< used for caching purposes
	std::string _allowed; ///< matches the allowed in node.def
	int node_type; ///< template's node type

	NodeParams _data; ///< this node's state
	std::vector<NodeParams> _children_coll; ///< contains either values, or switches
};

/**
 *
 *
 **/
class Configuration
{
public:
	typedef std::map<std::string,TemplateParams> CacheColl;
	typedef std::map<std::string,TemplateParams>::iterator CacheIter;

public:
	Configuration(bool debug = false);
	~Configuration();
	bool
	get_configured_node(const std::string &root_node, const std::string &conf_id, TemplateParams &params);

	bool
	get_operational_node(const std::string &data_path, TemplateParams &tmpl_params, bool is_admin);

	bool
	get_template_node(const std::string &path, TemplateParams &params);

private:
	bool
	get_op_template_node(const std::string &path, TemplateParams &params);
	bool
	is_allowed_node(std::string node);
	void setConfId(const std::string &conf_id);
	void getConvConfId(std::string &convconfid);
	void get_node_params(const std::string &cpath, NodeParams &node);

	void
	parse_value_and_state(const std::string &rel_data_path, const std::string &conf_id, TemplateParams &params);
	std::string _conf_id;
	std::string _conv_conf_id;
	struct configd_conn _conn;
	struct opd_connection _opd_conn;
	bool _debug;

private:
	/*
	 * If enabled, then don't reperform the directory looks up on the conf side of things if found in cache
	 *
	 */
	static bool _enable_cache;
	static CacheColl _conf_cache_coll;
	static CacheColl _op_cache_coll;
};


#endif //__CONFIGURATION_HH__
