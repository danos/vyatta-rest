/**
 * Module: chunker2_processor.hh
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2009, 2010 Vyatta, Inc.
 * All Rights Reserved.
 * Authors: Michael Larson
 * Date: 2010
 * Description: background process definitions
 *
 **/

#ifndef __CHUNKER_PROCESSOR_HH__
#define __CHUNKER_PROCESSOR_HH__

#include <string>
#include <vector>

class ChunkerProcessor
{
public:
	ChunkerProcessor() {}

	void
	init (unsigned long chunk_size, const std::string &pid_path, bool debug) {
		_chunk_size = chunk_size;
		_pid_path = pid_path;
		_debug = debug;
	}

	bool
	start_new(std::string token, const std::string &cmd, const std::string &user);

private:
	void
	writer(std::string token, const std::string &cmd,int (&cp)[2], std::string user);

	void
	tokenizeOpCmd(std::string &opmodecmd, std::vector<std::string> &opcmdarr);

	void
	reader(std::string token, int (&cp)[2]);

	std::string
	process_chunk(std::string &str, std::string &token);

	void
	process_chunk_end(std::string &str, std::string &token);

	void
	parse(char *line, char **argv);

	pid_t
	pid_output (const char *path);


private:
	unsigned long _chunk_size;
	std::string _pid_path;
	unsigned long _kill_timeout;
	bool _debug;
};

#endif //__CHUNKER_PROCESSOR_HH__
