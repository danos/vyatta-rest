/**
 * Module: authbasic.hh
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2009, 2010 Vyatta, Inc.
 * All Rights Reserved.
 * Authors: Michael Larson
 * Date: 2010
 * Description: authentication basic implementation
 *
 **/

#ifndef __AUTHBASIC_HH__
#define __AUTHBASIC_HH__

#include "http.hh"
#include "authbase.hh"

class AuthBasic : public AuthBase
{
public:
	friend class Authenticate;

public: //methods
	AuthBasic(bool debug) : AuthBase(debug) {}
	virtual ~AuthBasic() {}

	bool
	handle(const std::string &auth);

	bool
	authorized(const std::string &auth, Session &session);

private: //variables
};

#endif //__AUTHBASIC_HH__
