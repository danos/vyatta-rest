/**
 * Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
 * Copyright (c) 2014 by Brocade Communications Systems, Inc.
 * All rights reserved.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 **/

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <pwd.h>
#include <errno.h>
#include <syslog.h>
#include <vector>

#include "common.hh"
#include "http.hh"
#include "rl_str_proc.hh"
#include "mode.hh"

using namespace std;

int
Mode::system_out(const char *cmd, string &out)
{
  //  fprintf(out_stream,"system out\n");
  if (cmd == NULL) {
    return -1;
  }

  int cp[2]; // Child to parent pipe
  if( pipe(cp) < 0) {
    return -1;
  }

  pid_t pid = fork();
  if (pid == 0) {
    //child
    close(cp[0]);
    close(0); // Close current stdin.
    dup2(cp[1],STDOUT_FILENO); // Make stdout go to write end of pipe.
    dup2(cp[1],STDERR_FILENO); // Make stderr go to write end of pipe.
    //    fcntl(cp[1],F_SETFD,fcntl(cp[1],F_GETFD) & (~FD_CLOEXEC));
    close(cp[1]);
    int ret = 0;

    //set user and group here
    setregid(getegid(),getegid());
    setreuid(geteuid(),geteuid());

    // Don't leak this to the CLI since it might fetch URL's
    unsetenv("HTTP_PROXY");

    //    fprintf(out_stream,"executing: %s\n",cmd);
    if (execl("/bin/sh", "sh", "-c", cmd, NULL) == -1) {
      ret = errno;
    }
    close(cp[1]);
    exit(ret);
  }
  else {
    //parent
    vector<char> data;
    char buf[8192];
    memset(buf,'\0',8192);
    close(cp[1]);
    fd_set rfds;
    struct timeval tv;

    int flags = fcntl(cp[0], F_GETFL, 0);
    fcntl(cp[0], F_SETFL, flags | O_NONBLOCK);

    FD_ZERO(&rfds);
    FD_SET(cp[0], &rfds);
    tv.tv_sec = 1;
    tv.tv_usec = 0;
    while (select(FD_SETSIZE, &rfds, NULL, NULL, &tv) != -1) {
      int ret = 0;
      memset(buf,'\0',8192);
      if ((ret = read(cp[0], &buf, 8191)) > 0) {
	data.insert(data.end(), buf, buf+ret);
      }
      else if (ret == -1 && errno == EAGAIN) {
	//try again
      }
      else {
	break;
      }
      FD_ZERO(&rfds);
      FD_SET(cp[0], &rfds);
      tv.tv_sec = 1;
      tv.tv_usec = 0;

      fflush(NULL);
    }

    out = string(data.begin(), data.end());

    //now wait on child to kick the bucket
    int status;
    wait(&status);
    close(cp[0]);
    return WEXITSTATUS(status);
  }

}

void
Mode::handle_cmd_output(string &cmdout, Session &session)
{
  //scan for /r/n/n and process first section as response header overrides
  size_t pos = cmdout.find("\r\n\n");
  if (pos != string::npos) {
    string header = cmdout.substr(0,pos);
    //only allow client app _and_ client service to override content-type for now
    StrProc s(header,"\n");
    vector<string> coll = s.get();
    vector<string>::iterator iter = coll.begin();
    while (iter != coll.end()) {
      if (strncasecmp("Content-Type:",iter->c_str(),13) == 0) {
        if (iter->length() > 14) {
          session._response.set(Rest::HTTP_RESP_CONTENT_TYPE,iter->substr(14,iter->length()).c_str());
          session._response._verbatim_body = true; //assuming non-json format.
        }
      } else if (strncasecmp("Set-Cookie:",iter->c_str(),11) == 0) {
      	if (iter->length() > 12) {
      	  session._response.set(Rest::HTTP_RESP_COOKIE,iter->substr(12,iter->length()).c_str());
      	}
      } else if (strncasecmp("Cache-Control:",iter->c_str(),14) == 0) {
      	if (iter->length() > 14) {
          string cache_control = iter->substr(14,iter->length()).c_str();
          if (cache_control.find("vyatta-disable") != string::npos) {
            session._response.erase(Rest::HTTP_RESP_CACHE_CONTROL);
          } else {
           session._response.set(Rest::HTTP_RESP_CACHE_CONTROL, cache_control);
          }
      	}
      } else if (strncasecmp("Content-Disposition:",iter->c_str(),20) == 0) {
      	if (iter->length() > 20) {
          string disposition = iter->substr(20,iter->length()).c_str();
          session._response.set(Rest::HTTP_RESP_CONTENT_DISPOSITION, disposition);
      	}
      }
      ++iter;
    }

    if (cmdout.length() > pos) {
      cmdout = cmdout.substr(pos+3);
      session._response.set(Rest::HTTP_BODY,cmdout);
    }
  } else {
    session._response.set(Rest::HTTP_BODY,cmdout);
  }
}
