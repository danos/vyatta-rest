/**
 * Module: interface.hh
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2009, 2010 Vyatta, Inc.
 * All Rights Reserved.
 * Authors: Michael Larson
 * Date: 2010
 * Description: definitions for client object's interface to chunker
 *
 **/

#ifndef __MULTIRESPONSECOMMAND_HH__
#define __MULTIRESPONSECOMMAND_HH__

#include <string>
#include <vector>
#include <set>

/**
 *
 *
 **/
class ProcessData
{
public:
	std::string _username;
	unsigned long _start_time;
	unsigned long _last_update;
	std::string _id;
	std::string _command;
};

/**
 *
 *
 **/
class MultiResponseCommand
{
	typedef std::set<std::string> CmdColl;
	typedef std::set<std::string>::iterator CmdIter;

public:
	MultiResponseCommand(bool debug) : _debug(debug) {}
	virtual ~MultiResponseCommand();

	bool
	init();

	std::string
	start(std::string &user, std::string &cmd);

	ProcessData
	get_process_details(std::string &user, std::string &id);

	std::vector<ProcessData>
	get_processes(std::string &user);

	std::string
	get_chunk(std::string &user, std::string &id);

	void
	kill(std::string &user, std::string &id);

private:
	std::string
	get_next_resp_file(std::string &tok);

	std::string
	generate_token();

private:
	int _sock; //used to talk to chunker daemon
	bool _debug;
};
#endif //__MULTIRESPONSECOMMAND_HH__
