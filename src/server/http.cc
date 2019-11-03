/**
 * Module: http.cc
 * Description: session data management object
 *
 * Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
 * Copyright (c) 2009-2013 Vyatta, Inc.
 * All Rights Reserved.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 **/
#include <stdlib.h>
#include <string.h>
#include <cstdio>
#include <map>
#include <list>
#include <vector>
#include <string>
#include <jansson.h>
#include "http.hh"
#include "debug.h"

using namespace std;

/**
 *
 *
 **/
string
HTTP::get(const string &key)
{
	return string("");
}


/**
 *
 *
 **/
string
HTTP::get(const char *key)
{
	//  _param_coll.find(key);
	return string("");
}

/**
 *
 *
 **/
string
HTTP::get(Rest::KEY key)
{
	ParamIter iter = _param_coll.find(key);
	if (iter != _param_coll.end()) {
		return iter->second;
	}
	return string("");
}


/**
 *
 *
 **/
void
HTTP::set(Rest::KEY key, const string &val)
{
	_param_coll[key] = val;
}

/**
 *
 *
 **/
void
HTTP::set(Rest::KEY key, const char *val)
{
	if (val != NULL) {
		_param_coll[key] = string(val);
	}
}

/**
 *
 *
 **/
void
HTTP::append(Rest::KEY key, const std::string &val)
{
	string cur_val = get(key);
	cur_val += ","+val;
	set(key,cur_val);
}

/**
 *
 *
 **/
void
HTTP::erase(Rest::KEY key)
{
	_param_coll.erase(key);
}

/**
 *
 *
 **/
void
HTTP::parse(const string &stream)
{

}



/**
 *
 *
 **/
string
HTTP::serialize()
{
	string o,body;

	ParamIter iter = _param_coll.find(Rest::HTTP_RESP_CODE);
	if (iter != _param_coll.end()) {
		o = "Status: " + iter->second + "\r\n";
	}

	//verify the size of the response body if found
	iter = _param_coll.find(Rest::HTTP_BODY);
	if (iter != _param_coll.end()) {
		if (iter->second.length() > Rest::MAX_BODY_SIZE) {
			o = "Status: 500\r\n";
			//clear out response body then...
			iter->second = string("");
		}
	}


	iter = _param_coll.begin();
	while (iter != _param_coll.end()) {
		if (iter->first == Rest::HTTP_RESP_DEBUG) {
			o += "vyatta-debug: " + iter->second + "\r\n";
		} else if (iter->first == Rest::HTTP_RESP_WWWAUTH) {
			o += "WWW-Authenticate: " + iter->second + "\r\n";
		} else if (iter->first == Rest::HTTP_RESP_CONTENT_TYPE) {
			o += "Content-Type: " + iter->second + "\r\n";
		} else if (iter->first == Rest::HTTP_RESP_LOCATION) {
			o += "Location: " + iter->second + "\r\n";
		} else if (iter->first == Rest::HTTP_RESP_COOKIE) {
			o += "Set-Cookie: " + iter->second + "\r\n";
		} else if (iter->first == Rest::HTTP_RESP_CACHE_CONTROL) {
			o += "Cache-Control: " + iter->second + "\r\n";
		} else if (iter->first == Rest::HTTP_RESP_CONTENT_DISPOSITION) {
			o += "Content-Disposition: " + iter->second + "\r\n";
		} else if (iter->first == Rest::HTTP_RESP_VYATTA_SPECIFICATION_VERSION) {
			o += "Vyatta-Specification-Version: " + iter->second + "\r\n";
		} else if (iter->first == Rest::HTTP_BODY) {
			body = iter->second;

			//ensure this is in json format and reformat here!
			json_error_t error;
			if (!body.empty() && !_verbatim_body) {
				/* allocate a parser */
				json_t *jsonbody = json_loads(body.c_str(), JSON_DECODE_ANY, &error);
				if (jsonbody == NULL) {
					dsyslog(_debug, "HTTP::%s: %s", __func__, error.text);
				} else {
					char* obuf = json_dumps(jsonbody, JSON_ENCODE_ANY|JSON_COMPACT);
					if (obuf != NULL) {
						body = string((char*)obuf);
					}
					free(obuf);
				}
				json_decref(jsonbody);

			}
			char buf[80];
			snprintf(buf, sizeof(buf), "%zd", body.size());
			o += "Content-Length: " + string(buf) + "\r\n";
		}
		++iter;
	}

	//now tag the body onto the end as a hack right now...
	if (body.empty() == false) {
		o += "\r\n" + body;
	} else {
		o += "\r\n";
	}

	return o;
}

/**
 *
 *
 **/
string
HTTP::dump()
{
	string ret;
	ParamIter iter = _param_coll.begin();
	while (iter != _param_coll.end()) {
		if (iter->first == Rest::HTTP_REQ_URI) {
			ret += "req: uri";
		} else if (iter->first == Rest::HTTP_REQ_METHOD) {
			ret += "req: request_method";
		} else if (iter->first == Rest::HTTP_REQ_CONTENT_LENGTH) {
			ret += "req: content_length";
		} else if (iter->first == Rest::HTTP_REQ_AUTHORIZATION) {
			ret += "req: authorization";
		} else if (iter->first == Rest::HTTP_BODY) {
			ret += "body";
		} else if (iter->first == Rest::HTTP_RESP_DEBUG) {
			ret += "resp: debug";
		} else if (iter->first == Rest::HTTP_RESP_CODE) {
			ret += "resp: resp_code";
		} else if (iter->first == Rest::HTTP_RESP_CACHE_CONTROL) {
			ret += "resp: cache_control";
		} else {
			ret += iter->first;
		}
		ret += ":" + iter->second + "\r\n";
		++iter;
	}
	return ret;
}


/**
 *
 **/
void
JSON::add_array(string key, string &val, bool quoted)
{
	if (key.empty() || val.empty()) {
		return;
	}

	ArrayIter iter = _array.find(key);
	if (iter == _array.end()) {
		vector<string> c;
		if (quoted == false) {
			val = "\"" + val + "\"";
		}
		c.push_back(val);
		_array.insert(pair< string,vector<string> >(key,c));
	} else {
		if (quoted == false) {
			val = "\"" + val + "\"";
		}
		iter->second.push_back(val);
	}
}

/**
 *
 **/
void
JSON::add_value(string key, string &val)
{
	if (key.empty() || val.empty()) {
		return;
	}
	_value[key] = val;
}

/**
 *
 **/
void
JSON::add_value(string key, unsigned long val)
{
	if (key.empty()) {
		return;
	}
	char buf[20];
	sprintf(buf,"%ld",val);

	_value[key] = string(buf);
}

/**
 *
 **/
vector<string>
JSON::get_elements(std::string &key)
{
	ArrayIter iter = _array.find(key);
	if (iter != _array.end()) {
		return iter->second;
	}
	return vector<string>();
}

/**
 *
 **/
bool
JSON::add_hash(string key,JSON* &json)
{
	if (key.empty()) {
		return false;
	}
	_coll.insert(pair<string,JSON>(key,JSON()));
	JSONIter iter = _coll.find(key);
	json = &iter->second;
	return true;
}


/**
 *
 **/
JSON
JSON::get_hash(list<string> &keys)
{
	list<string>::iterator key_iter  = keys.begin();
	if (key_iter == keys.end()) {
		return JSON();
	}
	string key = *key_iter;
	keys.erase(key_iter);

	JSONIter iter = _coll.find(key);
	if (iter == _coll.end()) {
		return JSON();
	}
	if (keys.empty()) {
		return iter->second;
	}
	return iter->second.get_hash(keys); //recursion
}


//"help":{" Set user access",,}

/**
 *
 **/
void
JSON::serialize(string &rep)
{
	if (_array.empty() == true && _value.empty() == true && _coll.empty() == true) {
		return;
	}

	rep += "{";
	ArrayIter i = _array.begin();
	while (i != _array.end()) {
		vector<string>::iterator j = i->second.begin();
		if (j != i->second.end()) {
			rep += "\"" + i->first + "\":[";
			while (j != i->second.end()) {
				rep += *j + ",";
				++j;
			}
			rep = rep.substr(0,rep.length()-1);
			rep += "]";
		}
		rep += ",";
		++i;
	}

	//now serialize the values
	ValueIter ii = _value.begin();
	while (ii != _value.end()) {
		rep += "\"" + ii->first + "\":\"" + ii->second + "\",";
		++ii;
	}

	rep = rep.substr(0,rep.length()-1);
	rep += "}";

	//returned serialized json data
	JSONIter iii = _coll.begin();
	while (iii != _coll.end()) {
		string tmp;
		iii->second.serialize(tmp);
		rep += string(",") + tmp;
		++iii;
	}
}

/**
 * \brief Append dbgstr to response vyatta-debug header
 **/
void Session::vyatta_debug(const string &dbgstr)
{
	if (_debug)
		_response.append(Rest::HTTP_RESP_DEBUG, dbgstr);
}
