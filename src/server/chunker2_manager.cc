/**
 * Module: chunker2_manager.cc
 * Description: Manager for background processes
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
#include <netinet/in.h>
#include <sys/time.h>
#include <strings.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <syslog.h>
#include <unistd.h>
#include <fcntl.h>
#include <iostream>
#include <string>
#include <map>
#include "common.hh"
#include "chunker2_manager.hh"

using namespace std;

/**
 *
 **/
ChunkerManager::~ChunkerManager()
{
	//close the socket
	close(_listen_sock);
}

/**
 *
 **/
void
ChunkerManager::init()
{
	//clean up output directory on startup
	string clean_cmd = string("rm -f ") + Rest::CHUNKER_RESP_TOK_DIR + "/* >/dev/null";
	run_cmd(clean_cmd);

	string clean_connector = string("rm -f ") + Rest::CHUNKER_SOCKET;
	run_cmd(clean_connector);

	int servlen;
	struct sockaddr_un serv_addr;

	if ((_listen_sock = socket(AF_UNIX,SOCK_STREAM,0)) < 0) {
		cerr << "ChunkerManager::init(): error in creating listener socket" << endl;
		//    error("creating socket");
		return;
	}


	bzero((char *) &serv_addr, sizeof(serv_addr));
	serv_addr.sun_family = AF_UNIX;
	strcpy(serv_addr.sun_path, Rest::CHUNKER_SOCKET.c_str());
	servlen=strlen(serv_addr.sun_path) + sizeof(serv_addr.sun_family);
	if (bind(_listen_sock,(struct sockaddr *)&serv_addr,servlen)<0) {
		cerr << "ChunkerManager::init(): error in binding listener socket" << endl;
		return;
	}


	//set non-blocking
	int flags;
	if (-1 == (flags = fcntl(_listen_sock, F_GETFL, 0))) {
		flags = 0;
	}
	fcntl(_listen_sock, F_SETFL, flags | O_NONBLOCK);


	chmod(Rest::CHUNKER_SOCKET.c_str(),S_IROTH|S_IWOTH|S_IXOTH|S_IRGRP|S_IWGRP|S_IXGRP|S_IRUSR|S_IWUSR|S_IXUSR);
}

/**
 * listen for commands from pipe
 **/
void
ChunkerManager::read()
{
	char buf[1025];
	struct sockaddr_un  cli_addr;
	//listen for new connection
	listen(_listen_sock,5);
	int clilen = sizeof(cli_addr);
	int clientsock = accept(_listen_sock,(struct sockaddr *)&cli_addr,(socklen_t*)&clilen);
	if (clientsock > -1) {
		printf("ChunkerManager::read(), new connection\n");
		int n = ::read(clientsock,buf,1024);
		printf("Read %d bytes from socket: %s\n",n,buf);
		buf[n] = '\0';
		process(clientsock,buf);
		//done processing now close the socket
		close(clientsock);
	} else {
		//    process(NULL);
	}

	return;
}


/**
 *
 **/
void
ChunkerManager::process(int sock, char *buf)
{
	/****
	     ADD CMD PROCESSOR HERE FOR DATA FROM THE SOCKET
	 ****/
	struct timeval t;
	gettimeofday(&t,NULL);
	unsigned long cur_time = t.tv_sec;

	if (sock == 0 || buf == NULL) {
		return;
	}

	if (_debug) {
		cout << "ChunkerManager::process(), processing message" << endl;;
	}

	if (buf != NULL) {
		string command = string(buf);

		string token;
		size_t start_pos = command.find("<token>");
		size_t stop_pos = command.find("</token>");
		if (start_pos == string::npos || stop_pos == string::npos) {
			return; //doesn't have a token, then ignore request and return
		} else {
			token = command.substr(start_pos+7,stop_pos-start_pos-7);
		}

		//now grab the command
		string statement;
		start_pos = command.find("<statement>");
		stop_pos = command.find("</statement>");
		if (start_pos == string::npos || stop_pos == string::npos) {
			//do nothing here
		} else {
			statement = command.substr(start_pos+11,stop_pos-start_pos-11);
		}

		//finally grab the user
		string user;
		start_pos = command.find("<user>");
		stop_pos = command.find("</user>");
		if (start_pos == string::npos || stop_pos == string::npos) {
			//do nothing here
		} else {
			user = command.substr(start_pos+6,stop_pos-start_pos-6);
		}


		if (command.find("<command>") != string::npos) {
			//grab the token
			if (_debug) {
				cout << "ChunkerManager::process(): command received, token: " << token << ", statement: " << statement << ", user: " << user << endl;
			}

			//finally convert the token to a key
			string key = token;

			//ALSO NEED TO MATCH THE COMMAND TO SEE IF THIS IS A NEW OR ONGOING COMMAND
			ProcIter iter = _proc_coll.find(key);
			if (iter != _proc_coll.end() && statement.empty()) {
				iter->second._last_update = cur_time; //update time
			} else {
				ProcessData pd;
				pd._start_time = pd._last_update = cur_time;
				pd._token = token;
				pd._command = statement;
				pd._user = user;
				pd._status = ProcessData::K_RUNNING;

				//now start up the procesor
				pd._proc.init(_chunk_size,_pid,_debug);

				if (pd._proc.start_new(token,statement,user) == false) {
					return;
				}

				if (_debug) {
					cout << "inserting new process into table: " << key << ", current table size: " << _proc_coll.size() << endl;
				}
				_proc_coll.insert(pair<string, ProcessData>(key,pd));
			}
		} else if (command.find("<process>") != string::npos) {
			if (_debug) {
				cout << "received process query: " << user << endl;
			}

			string resp;
			ProcIter iter = _proc_coll.begin();
			while (iter != _proc_coll.end()) {
				if (iter->second._user != user) {
					++iter;
					continue;
				}
				sprintf(buf,"%ld",iter->second._start_time);
				resp += string(buf) + "%3A" + iter->second._command + "%3A" + iter->second._token + "%3A" + iter->second._user;
				sprintf(buf,"%ld",iter->second._read_offset);
				resp += string("%3A") + string(buf) + "%2C";
				++iter;
			}
			if (_debug) {
				cout << "responding with: " << resp << endl;
			}
			if (write(sock,resp.c_str(),resp.length()) < 0) {
				return;
			}
		} else if (command.find("<details>") != string::npos) {
			//information about a specific process
			if (_debug) {
				cout << "received process query: " << user << endl;
			}

			string resp;
			ProcIter iter = _proc_coll.begin();
			while (iter != _proc_coll.end()) {
				if (iter->second._user != user) {
					++iter;
					continue;
				}
				if (token != iter->second._token) {
					++iter;
					continue;
				}
				sprintf(buf,"%ld",iter->second._start_time);
				resp += string(buf) + "%3A" + iter->second._command + "%3A" + iter->second._token + "%3A" + iter->second._user;
				sprintf(buf,"%ld",iter->second._read_offset);
				resp += string("%3A") + string(buf) + "%2C";
				++iter;
			}
			if (_debug) {
				cout << "responding with: " << resp << endl;
			}
			if (write(sock,resp.c_str(),resp.length()) < 0) {
				return;
			}
		} else if (command.find("<next>") != string::npos) {
			//increment count IF chunk is available.
			string resp;
			ProcIter iter = _proc_coll.find(token);
			if (iter != _proc_coll.end()) {
				if (user != iter->second._user) {
					//don't let someone else browse this data
					resp = "";
				} else {
					sprintf(buf,"%ld",iter->second._read_offset);
					string chunk_file = Rest::CHUNKER_RESP_TOK_DIR + Rest::CHUNKER_RESP_TOK_BASE + token;
					sprintf(buf,"%ld",iter->second._start_time);
					resp = string(buf) + "%3A" + iter->second._command + "%3A" + iter->second._token + "%3A" + iter->second._user;

					if (iter->second._status == ProcessData::K_DEAD) {
						iter->second._read_offset = -1; //denotes a terminated process that has been completely read
					}

					sprintf(buf,"%ld",iter->second._read_offset);
					resp += string("%3A") + string(buf) + "\n";

					struct stat s;
					if ((lstat(chunk_file.c_str(), &s) == 0)) {
						//ok to increment
						if ((unsigned)s.st_size > (iter->second._read_offset + _chunk_size)) {
							iter->second._read_offset += _chunk_size;
						} else {
							iter->second._read_offset = s.st_size; //will allow the file to be read to the limit
							//but first check to see if we are at the end of the file....
							string end_file = Rest::CHUNKER_RESP_TOK_DIR + Rest::CHUNKER_RESP_TOK_BASE + token + "_end";
							if (lstat(end_file.c_str(),&s) == 0) {
								iter->second._status = ProcessData::K_DEAD;
							}
						}
					}
				}
			} else {
				resp = "  ";
			}
			if (write(sock,resp.c_str(),resp.length()) < 0) {
				if (_debug) {
					cout << "error writing response: " << resp << endl;
				}
			}
		} else if (command.find("<delete>") != string::npos) {
			if (_debug) {
				cout << "received process query: " << user << endl;
			}
			kill_process(token);
		}
	}
}

/**
 *
 **/
void
ChunkerManager::kill_all()
{
	ProcIter iter = _proc_coll.begin();
	while (iter != _proc_coll.end()) {
		if (!iter->first.empty()) {
			kill_process(iter->first);
		}
		++iter;
	}
}

/**
 *
 **/
void
ChunkerManager::shutdown()
{
	kill_all();
	//clean up output directory on startup
	string clean_cmd = string("rm -f ") + Rest::CHUNKER_RESP_TOK_DIR + "/* >/dev/null";
	run_cmd(clean_cmd);
}

/**
 *
 **/
void
ChunkerManager::kill_process(string key)
{
	string term_cmd = "kill -15 -"; //now is expecting to kill group
	string kill_cmd = "kill -9 -";

	//need to get pid from pid directory...
	string file = Rest::CHUNKER_RESP_PID + "/" + key;
	FILE *fp = fopen(file.c_str(), "r");
	char pid[81];
	size_t rslt;

	if (fp) {
		rslt = fread(pid, sizeof(char), sizeof(pid) - 1, fp);
		fclose(fp);
		if (rslt < 1) {
			syslog(LOG_ERR, "webgui: Unable to read pid");
			return;
		}
	} else {
		return;
	}

	unlink(file.c_str());
	//little hammer
	term_cmd += string(pid);
	//big hammer
	kill_cmd += string(pid);

	int ct = 3; //attempt three times.
	string exist_file = "/proc/" + string(pid) + "/stat";
	bool killed = false;
	while (ct > 0) {
		run_cmd(term_cmd);
		sleep(1); //one second
		//does process still exist?
		struct stat s;
		if (stat(exist_file.c_str(), &s) == -1) {
			killed = true;
			break;
		}
		--ct;
	}

	if (killed == false) {
		//now use big hammer
		run_cmd(kill_cmd);
	}
	//now remove entry from proc map:
	_proc_coll.erase(key);
}

/**
 * \brief Run the specified command
 **/
bool
ChunkerManager::run_cmd(const string &cmd)
{
	int status;

	status = system(cmd.c_str());
	if (status == -1) {
		cerr << "Unable to run command: " << cmd << endl;
	} else if (WIFEXITED(status)) {
		status = WEXITSTATUS(status);
	} else if (WIFSIGNALED(status)) {
		cerr << "Signal " << WTERMSIG(status) << " terminated command: " << cmd << endl;
		status = -1;
	} else {
		cerr << "Unexpected return from command: " << cmd << endl;
		status = -1;
	}
	return (status == 0);
}
