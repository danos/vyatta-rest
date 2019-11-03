/**
 * Module: chunker2_manager.hh
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2009, 2010 Vyatta, Inc.
 * All Rights Reserved.
 * Authors: Michael Larson
 * Date: 2010
 * Description: definitions for background process manager
 *
 **/

#ifndef __CHUNKER_MANAGER_HH__
#define __CHUNKER_MANAGER_HH__

#include <string>
#include <map>
#include "chunker2_processor.hh"

class ProcessData
{
public:
	typedef enum {K_NONE, K_RUNNING, K_DEAD} ProcStatus;

public:
	ProcessData() :
		_start_time(0),
		_last_update(0),
		_read_offset(0),
		_status(K_NONE)
	{}

public:
	ChunkerProcessor _proc;
	unsigned long _start_time;
	unsigned long _last_update;
	std::string _command;
	std::string _token; //is the string version of the key
	std::string _user;
	unsigned long _read_offset;
	ProcStatus _status;
};

class ChunkerManager
{
public:
	typedef std::map<std::string, ProcessData> ProcColl;
	typedef std::map<std::string, ProcessData>::iterator ProcIter;

public:
	ChunkerManager(const std::string &pid, unsigned long kill_timeout, unsigned long chunk_size, bool debug) :
		_pid(pid),
		_kill_timeout(kill_timeout),
		_chunk_size(chunk_size),
		_debug(debug) {}
	~ChunkerManager();

	void
	init();

	//listens on pipe for message from webserver
	void
	read();

	void
	kill_all();

	void
	shutdown();

private:
	void
	process(int socket, char *buf);

	void
	kill_process(std::string key);

	bool run_cmd(const std::string &cmd);

private:
	ProcColl _proc_coll;
	std::string _pid;
	int _listen_sock;
	unsigned long _kill_timeout;
	unsigned long _chunk_size;
	bool _debug;
};

#endif //__CHUNKER_MANAGER_HH__
