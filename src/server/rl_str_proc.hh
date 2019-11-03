/**
 * Module: rl_str_proc.hh
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2009, 2010 Vyatta, Inc.
 * All Rights Reserved.
 * Authors: Michael Larson
 * Date: 2010
 * Description: definition for string processing support
 *
 **/

#ifndef __RL_STR_PROC_HH__
#define __RL_STR_PROC_HH__

#include <vector>
#include <string>

class StrProc
{
public:
	StrProc(const std::string &in, const std::string &token);

	std::string get(int i);

	std::string get(int start, int end);

	std::vector<std::string> get();

	int size() {
		return _str_coll.size();
	}

private:
	std::vector<std::string> _str_coll;
};

#endif //__RL_STR_PROC_HH__
