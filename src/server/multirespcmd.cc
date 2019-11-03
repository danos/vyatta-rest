/**
 * Module: multirespcmd.cc
 * Description: client side interface for chunker
 *
 * Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
 * Copyright (c) 2009-2013 Vyatta, Inc.
 * All Rights Reserved.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 **/

#include <cstdio>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <vector>
#include <string>
#include <syslog.h>
#include <iostream>
#include "rl_str_proc.hh"
#include "common.hh"
#include "multirespcmd.hh"
#include "debug.h"

using namespace std;

/**
 *
 **/
MultiResponseCommand::~MultiResponseCommand()
{
	close(_sock);
}

/**
 *
 **/
bool
MultiResponseCommand::init()
{
	int servlen;
	struct sockaddr_un  serv_addr;

	dsyslog(_debug, "%s: MultiResponseCommand::init(A)", __func__);

	bzero((char *)&serv_addr,sizeof(serv_addr));
	serv_addr.sun_family = AF_UNIX;
	strcpy(serv_addr.sun_path, Rest::CHUNKER_SOCKET.c_str());
	servlen = strlen(serv_addr.sun_path) + sizeof(serv_addr.sun_family);
	if ((_sock = socket(AF_UNIX, SOCK_STREAM,0)) < 0) {
		return false;
	}
	if (connect(_sock, (struct sockaddr *)&serv_addr, servlen) < 0) {
		return false;
	}

	dsyslog(_debug, "%s: MultiResponseCommand::init(B)", __func__);
	return true;
}

/**
 *
 *
 **/
string
MultiResponseCommand::start(string &user, string &cmd)
{
	string tok = Rest::generate_token();
	if (tok.length() < 16) {
		syslog(LOG_ERR, "Unable to obtain token");
		return "";
	}

	char buffer[1024];
	bzero(buffer,1024);
	sprintf(buffer,Rest::CHUNKER_COMMAND_FORMAT.c_str(),tok.c_str(),cmd.c_str(),user.c_str());

	if (write(_sock,buffer,sizeof(buffer)) == -1) {
		char buf[1024];
		sprintf(buf,"Error on initiating operational mode command: %d",errno);
		syslog(LOG_ERR, "%s", buf);
		return "";
	}

	return tok;
}

ProcessData
MultiResponseCommand::get_process_details(string &user, string &id)
{
	ProcessData pd;
	if (user.empty() || id.empty()) {
		return pd;
	}

	char in[1024];
	bzero(in,1024);
	sprintf(in,Rest::CHUNKER_DETAILS_FORMAT.c_str(),id.c_str(),user.c_str());

	if (write(_sock,in,sizeof(in)) == -1) {
		return pd;
	}

	//now read from the sock...
	char out[8192];
	bzero(out,8192);
	if (read(_sock,out,sizeof(out)) == -1) {
		return pd;
	}

	//now stuff into procs and return.
	StrProc sp(out,"%2C");
	vector<string> coll = sp.get();
	vector<string>::iterator iter = coll.begin();
	if (iter != coll.end()) {
		StrProc sp2(*iter,"%3A");
		pd._start_time = strtoul(sp2.get(0).c_str(),NULL,10);
		pd._command = sp2.get(1);
		pd._id = sp2.get(2);
		pd._username = sp2.get(3);
	}
	return pd;
}

/**
 *
 *
 **/
vector<ProcessData>
MultiResponseCommand::get_processes(string &user)
{
	vector<ProcessData> procs;
	string tok("123456");

	if (user.empty()) {
		return procs;
	}

	char in[1024];
	bzero(in,1024);
	sprintf(in,Rest::CHUNKER_PROCESS_FORMAT.c_str(),tok.c_str(),user.c_str());

	if (write(_sock,in,sizeof(in)) == -1) {
		return procs;
	}

	//now read from the sock...
	char out[8192];
	bzero(out,8192);
	if (read(_sock,out,sizeof(out)) == -1) {
		return procs;
	}

	//now stuff into procs and return.
	StrProc sp(out,"%2C");
	vector<string> coll = sp.get();
	vector<string>::iterator iter = coll.begin();
	while (iter != coll.end()) {
		ProcessData pd;
		StrProc sp2(*iter,"%3A");
		pd._start_time = strtoul(sp2.get(0).c_str(),NULL,10);
		pd._command = sp2.get(1);
		pd._id = sp2.get(2);
		pd._username = sp2.get(3);
		procs.push_back(pd);
		++iter;
	}
	return procs;
}


/**
 * used for reading in next chunk of data and returning.
 *
 **/
string
MultiResponseCommand::get_chunk(string &user,string &token)
{
	string resp;
	char in[1024];

	if (user.empty() || token.empty()) {
		return resp;
	}

	bzero(in,1024);
	sprintf(in,Rest::CHUNKER_NEXT_FORMAT.c_str(),token.c_str(),user.c_str());

	if (write(_sock,in,sizeof(in)) == -1) {
		return resp;
	}

	//now read from the sock...
	char out[8192];
	bzero(out,8192);
	if (read(_sock,out,sizeof(out)) == -1) {
		return resp;
	}
	//now stuff into procs and return.
	StrProc sp2(string(out),"%3A");
	std::string chunk = sp2.get(4);
	if (chunk.empty() == true) {
		return resp;
	}

	//now read in the stuff
	string file_chunk = Rest::CHUNKER_RESP_TOK_DIR + Rest::CHUNKER_RESP_TOK_BASE + token;

	long chunk_pos = strtol(chunk.c_str(),NULL,10);
	if (chunk_pos == 0 && errno == EINVAL) {
		return resp;
	}

	struct stat s;
	if ((lstat(file_chunk.c_str(), &s) == 0) && S_ISREG(s.st_mode) && chunk_pos >= 0) {
		//found chunk now read next
		FILE *fp = fopen(file_chunk.c_str(), "r");

		if (fp) {
			fflush(fp);
			if (chunk_pos > 0) {
				if (fseek(fp,chunk_pos,SEEK_SET) != 0) {
					fclose(fp);
					return resp;
				}
			}

			char buf[Rest::CHUNKER_READ_SIZE+1];
			bzero(buf,Rest::CHUNKER_READ_SIZE+1);
			int left = Rest::CHUNKER_READ_SIZE;
			int read = 0;
			int ct = 0;
			while ((left > 0) && (read = fread(buf,1,left,fp)) > -1) {
				left = left - read;
				if (read > 0) {
					resp += string(buf);
				}
				if (feof(fp) != 0) {
					break;
				}
				if (++ct > 5) {
					break; //let's only attempt this 5 times then give up.
				}
				bzero(buf,Rest::CHUNKER_READ_SIZE);
			}
			fclose(fp);
		}
	} else { //need to determine if the chunker is done, or the request needs to be resent
		//will look for end file, otherwise return true
		string end_file = Rest::CHUNKER_RESP_TOK_DIR + Rest::CHUNKER_RESP_TOK_BASE + token + "_end";
		if ((lstat(end_file.c_str(), &s) == 0)) {
			resp = "END";
			unlink(end_file.c_str());

			string data_file = Rest::CHUNKER_RESP_TOK_DIR + Rest::CHUNKER_RESP_TOK_BASE + token;
			unlink(data_file.c_str());
		}
	}
	return resp;
}


/**
 *
 *
 **/
void
MultiResponseCommand::kill(string &user, string &tok)
{
	char buffer[1024];
	bzero(buffer,1024);

	if (user.empty() || tok.empty()) {
		return;
	}

	sprintf(buffer,Rest::CHUNKER_DELETE_FORMAT.c_str(),tok.c_str(),user.c_str());

	ssize_t num = write(_sock,buffer,sizeof(buffer));
	if (num < 0) {
		//    char buf[80];
		//    sprintf(buf,"%d, and %d",num,errno);
		return;
	}
	return;
}

