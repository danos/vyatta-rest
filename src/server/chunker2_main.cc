/**
 * Module: chunker2_main.cc
 * Description: background process main entry point
 *
 * Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
 * Copyright (c) 2009-2013 Vyatta, Inc.
 * All Rights Reserved.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 **/
#include <unistd.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <syslog.h>
#include <sys/sysinfo.h>
#include <signal.h>
#include <stdlib.h>
#include <syslog.h>
#include <stdio.h>
#include <iostream>
#include <string>
#include "common.hh"
#include "chunker2_processor.hh"
#include "chunker2_manager.hh"

using namespace std;

bool g_shutdown = false;


pid_t
pid_output (const char *path);

/**
 *
 **/
static void usage()
{
	cout << "chunker -sipkdh" << endl;
	cout << "  -s chunk size" << endl;
	cout << "  -i session pid path" << endl;
	cout << "  -p process pid path" << endl;
	cout << "  -k kill timeout (seconds)" << endl;
	cout << "  -d debug" << endl;
	cout << "  -h help" << endl;
}

/**
 *
 **/
static void sig_end(int signo)
{
	g_shutdown = true;
	syslog(LOG_ERR, "webgui_chunker, exit signal caught, exiting..");
}

/**
 *
 **/
int main(int argc, char* argv[])
{
	int ch;
	string pid_path = Rest::CHUNKER_RESP_PID;
	string command, token;
	string process_pid_path;
	long chunk_size = Rest::CHUNKER_READ_SIZE;
	unsigned long kill_timeout = 300; //5 minutes
	bool debug = false;

	signal(SIGINT, sig_end);
	signal(SIGTERM, sig_end);

	//grab inputs
	while ((ch = getopt(argc, argv, "s:i:p:k:dh")) != -1) {
		switch (ch) {
		case 's':
			chunk_size = strtoul(optarg,NULL,10);
			if (chunk_size < 1024 || chunk_size > 131072) {  //to 2^17
				chunk_size = Rest::CHUNKER_READ_SIZE;
			}
			break;
		case 'i':
			pid_path = optarg;
			break;
		case 'p':
			process_pid_path = optarg;
			break;
		case 'k':
			kill_timeout = strtoul(optarg,NULL,10);
			if (kill_timeout > 86400) { //one hour
				kill_timeout = 86400;
			}
			break;
		case 'd':
			debug = true;
			break;
		case 'h':
		default:
			usage();
			exit(0);
		}
	}

	if (fork() != 0) {
		int s;
		//parent will wait until everything is done
		wait(&s);
		exit(0);
	}

	if (process_pid_path.empty() == false) {
		pid_output(process_pid_path.c_str());
	}

	//now set up the manager and the processor objects
	ChunkerManager mgr(pid_path,kill_timeout,chunk_size,debug);

	mgr.init();
	while (g_shutdown == false) {
		if (debug == true) {
			cout << "waiting on read of data" << endl;
		}
		mgr.read();
		usleep(200 * 1000); //.2 second sleep
	}

	mgr.shutdown();
	usleep(2 * 1000 * 1000); //lets give these guys a bit of time to shut down
	exit(0);
}

/**
 *
 *below borrowed from quagga library.
 **/
#define PIDFILE_MASK 0644
pid_t
pid_output (const char *path)
{
	FILE *fp;
	pid_t pid;
	mode_t oldumask;

	pid = getpid();

	oldumask = umask(0777 & ~PIDFILE_MASK);
	fp = fopen (path, "w");
	if (fp != NULL) {
		fprintf (fp, "%d\n", (int) pid);
		fclose (fp);
		umask(oldumask);
		return pid;
	}
	/* XXX Why do we continue instead of exiting?  This seems incompatible
	   with the behavior of the fcntl version below. */
	umask(oldumask);
	return -1;
}
