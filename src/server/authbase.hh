/**
 * Module: authbase.hh
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2009, 2010 Vyatta, Inc.
 * All Rights Reserved.
 * Authors: Michael Larson
 * Date: 2010
 * Description: authentication base class
 *
 **/

#ifndef __AUTHBASE_HH__
#define __AUTHBASE_HH__

#include <string>
#include "http.hh"

class AuthBase
{
public: //methods
	AuthBase(bool debug) : _debug(debug) {}
	virtual ~AuthBase() {}

	virtual bool
	handle(const std::string &auth) = 0;

	virtual bool
	authorized(const std::string &auth, Session &session) = 0;

protected: //variables
	bool _debug;
};

#endif //__AUTHBASE_HH__
