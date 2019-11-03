/**
 * Module: authenticate.hh
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2009, 2010 Vyatta, Inc.
 * All Rights Reserved.
 * Authors: Michael Larson
 * Date: 2010
 * Description: definitions for authentication
 *
 **/

#ifndef __AUTHENTICATE_HH__
#define __AUTHENTICATE_HH__

#include <vector>
#include "http.hh"
#include "authbase.hh"

class Authenticate
{
public:
	typedef std::vector<AuthBase*> AuthColl;
	typedef std::vector<AuthBase*>::iterator AuthIter;

public: //methods
	Authenticate(bool debug);

	bool
	validate(Session &session);

private: //methods


private: //variables
	AuthColl _auth_coll;
	bool _debug;
};

#endif //__AUTHENTICATE_HH__
