/**
 * Module: http.hh
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2009, 2010 Vyatta, Inc.
 * All Rights Reserved.
 * Authors: Michael Larson
 * Date: 2010
 * Description: session object definition
 *
 **/

#ifndef __HTTP_HH__
#define __HTTP_HH__

#include <map>
#include <list>
#include <vector>
#include <string>
#include "common.hh"

#define ERROR Error e

class HTTP
{
public:
	typedef std::map<Rest::KEY,std::string> ParamColl;
	typedef std::map<Rest::KEY,std::string>::iterator ParamIter;

public:
	HTTP(bool debug) :
		_debug(debug),
		_verbatim_body(false)
	{}
	virtual ~HTTP() {}

	std::string
	get(const char *key);

	std::string
	get(const std::string &key);

	std::string
	get(Rest::KEY key);

	void
	set(Rest::KEY key, const std::string &value);

	void
	set(Rest::KEY key, const char *value);

	void
	append(Rest::KEY key, const std::string &value);

	void
	erase(Rest::KEY key);

	void
	parse(const std::string &stream);

	std::string
	serialize();

	std::string
	dump();

private:
	ParamColl _param_coll;
	bool _debug;
public:
	bool _verbatim_body;
};



class Session
{
public:
	typedef enum {k_VYATTACFG, k_VYATTAOP, k_VYATTASERVICE_USER} AccessLevel;
public:
	Session(bool debug) :
		_debug(debug),
		_request(debug),
		_response(debug),
		_access_level(k_VYATTAOP),
		_service_user(false),
		_auth_type(Rest::AUTH_TYPE_NONE) {}

	void vyatta_debug(const std::string &dbgstr);

public:
	bool _debug;
	HTTP _request;
	HTTP _response;

	std::string _user;
	AccessLevel _access_level;
	bool _service_user;

	//below should be converted into authentication object w/ accessors
	Rest::AUTH_ACCESS_TYPE _auth_type;
	std::string _session_key;
};


class JSON
{
public:
	typedef std::map<std::string,JSON> JSONColl;
	typedef std::map<std::string,JSON>::iterator JSONIter;
	typedef std::map< std::string,std::vector<std::string> > Array;
	typedef std::map< std::string,std::vector<std::string> >::iterator ArrayIter;
	typedef std::map< std::string,std::string> Value;
	typedef std::map< std::string,std::string>::iterator ValueIter;

public:
	JSON() {}
	virtual ~JSON() {}

	void
	add_array(std::string key, std::string &val, bool quoted = false);

	void
	add_value(std::string key, std::string &val);

	void
	add_value(std::string key, unsigned long val);

	std::vector<std::string>
	get_elements(std::string &key);

	bool
	add_hash(std::string key, JSON* &json);

	JSON
	get_hash(std::list<std::string> &key);

	void
	serialize(std::string &rep);

private:
	JSONColl _coll;
	Array _array;
	Value _value;
};



class Error
{
public:
	typedef enum {
		OK,
		CREATED,
		ACCEPTED,
		VALIDATION_FAILURE,
		CONFIGURATION_ERROR,
		APPMODE_SCRIPT_ERROR, //used primary to specify webgui2 modified by cli
		SERVICEMODE_SCRIPT_ERROR,
		CONFMODE_DUP_DESC_ERROR,
		AUTHORIZATION_FAILURE,
		COMMAND_NOT_FOUND,
		OPMODE_PROCESS_FINISHED,
		SERVER_ERROR,
		SERVER_COMMAND_ERROR,
		ENTITLEMENT_ERROR
	} ERROR_TYPE;

public:
	Error(Session &session,ERROR_TYPE type) {
		Error(session,type,"");
	}
	Error(Session &session,ERROR_TYPE type, std::string msg) {

		std::string http_response_error[][3] = {
			{"200","",""},
			{"201","",""},
			{"202","",""},
			{"400","Validation failure","0"},
			{"400","",""},
			{"400","",""},
			{"400","Service command error","1"},
			{"400","Duplicate configuration description","1"},
			{"401","Authorization failure","0"},
			{"404","Command not found","0"},
			{"410","",""},
			{"500","Server error","0"},
			{"500","",""},
			{"503","Entitlement error","2"}
		};

		JSON json;
		if (msg.empty() == true) {
			json.add_value("message",http_response_error[int(type)][1]);
		} else {
			std::string s(http_response_error[int(type)][1] + ": " + msg);
			json.add_value("message",s);
		}
		json.add_value("error",http_response_error[int(type)][2]);

		std::string resp;
		json.serialize(resp);
		if (resp.empty() == false) {
			session._response.set(Rest::HTTP_BODY,resp);
		}
		session._response.set(Rest::HTTP_RESP_CODE, http_response_error[int(type)][0]);
	}
	virtual ~Error() {}
};



#endif //__HTTP_HH__
