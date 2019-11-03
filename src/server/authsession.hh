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

#ifndef __AUTHSESSION_HH__
#define __AUTHSESSION_HH__

#include <sys/types.h>
#include <sys/stat.h>
#include "http.hh"
#include "authbase.hh"

class Lock
{
public:
	const static unsigned long _retry_lock_interval;
	const static unsigned long _retry_lock_count;

public:
	Lock(const std::string &file);
	virtual ~Lock();

	bool
	status() {
		return _status;
	}

	FILE*
	get_fp() {
		return _fp;
	}

	FILE*
	get_fp_tmp() {
		return _fp_tmp;
	}

private:
	std::string _file;
	FILE* _fp;
	FILE* _fp_tmp;
	int _lck_fd;
	bool _status;
	mode_t _mask;
};



class AuthSession : protected AuthBase
{
public:
	friend class Authenticate;

public: //methods
	AuthSession(bool debug);
	virtual ~AuthSession() {}

	bool
	handle(const std::string &auth);

	bool
	authorized(const std::string &auth, Session &session);

private: //variables
	const static std::string _session_file;
	const static unsigned long _session_timeout;
};

#endif //__AUTHSESSION_HH__
