/**
 * Module: common.hh
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2009, 2010 Vyatta, Inc.
 * All Rights Reserved.
 * Authors: Michael Larson
 * Date: 2010
 * Description: common definitions used in the webgui2 project
 *
 **/

#ifndef __COMMON_HH__
#define __COMMON_HH__

#include <sys/time.h>
#include <string>
#include <sstream>

typedef void CURL;

class Timer
{
public:
	Timer(std::string id);
	~Timer();

private:
	struct timeval _start_time;
	std::string _id;
};

class Rest
{
public:
	typedef enum {
		HTTP_REQ_URI,
		HTTP_REQ_AUTHORIZATION,
                HTTP_REQ_COOKIE,
		HTTP_REQ_QUERY_STRING,
		HTTP_REQ_METHOD,
		HTTP_REQ_CONTENT_LENGTH,
		HTTP_REQ_VYATTA_SPECIFICATION_VERSION,
		HTTP_REQ_ACCEPT,
		HTTP_REQ_HOST,
		HTTP_REQ_PRAGMA,
		HTTP_RESP_DEBUG,
		HTTP_RESP_CODE,
		HTTP_RESP_WWWAUTH,
		HTTP_RESP_CONTENT_TYPE,
		HTTP_RESP_LOCATION,
		HTTP_RESP_COOKIE,
		HTTP_RESP_VYATTA_SPECIFICATION_VERSION,
		HTTP_RESP_CACHE_CONTROL,
                HTTP_RESP_CONTENT_DISPOSITION,
		HTTP_BODY
	} KEY;

	typedef enum {
		POST,
		GET,
		DELETE,
		PUT
	} HTTP_METHOD;

	typedef enum {
		AUTH_TYPE_NONE,
		AUTH_TYPE_BASIC,
		AUTH_TYPE_VYATTA_SESSION
	} AUTH_ACCESS_TYPE;

	//NODE DEFINITIONAL STUFF HERE
	enum Attributes {NOATTR = 0,
	                 OP,
	                 CONF,
	                 APP
	                };

	enum NodeType {NONE = 0,
	               TEXT,
	               IPV4,
	               IPV4NET,
	               IPV6,
	               IPV6NET,
	               U32,
	               BOOL,
	               MACADDR
	              };


	enum SubcodeErrors {k_SC_ERR_NONE = 0,
	                    k_SC_ERR_DUP_DESC,
	                    k_SC_ERR_ENTITLEMENT
	                   };

	const static std::string AUTH_BASIC;
	const static std::string AUTH_VYATTA_SESSION;
	const static std::string AUTH_VYATTA_PATH_LOC;
	const static std::string PRAGMA_NO_VYATTA_SESSION_UPDATE;
	const static std::string PRAGMA_SERVICE_USER;


	static std::string REST_SERVER_VERSION;

	static std::string JSON_INPUT;
	static unsigned long MAX_BODY_SIZE;
	static unsigned long PROC_KEY_LENGTH;

	static std::string CONF_REQ_ROOT;
	static std::string OP_REQ_ROOT;
	static std::string APP_REQ_ROOT;
	static std::string SERVICE_REQ_ROOT;
	static std::string PERM_REQ_ROOT;

	//op mode stuff here
	const static std::string OP_COMMAND_DIR;
	const static std::string CONF_COMMAND_DIR;
	const static std::string SERVICE_COMMAND_DIR;
	const static std::string CHUNKER_RESP_CMDS;
	const static std::string CHUNKER_RESP_TOK_DIR;
	const static std::string CHUNKER_RESP_TOK_BASE;
	const static std::string CHUNKER_RESP_PID;
	const static std::string CHUNKER_SOCKET;
	const static unsigned long CHUNKER_READ_SIZE;
	const static unsigned long CHUNKER_MAX_WAIT_TIME;
	const static std::string CHUNKER_COMMAND_FORMAT;
	const static std::string CHUNKER_PROCESS_FORMAT;
	const static std::string CHUNKER_DETAILS_FORMAT;
	const static std::string CHUNKER_NEXT_FORMAT;
	const static std::string CHUNKER_UPDATE_FORMAT;
	const static std::string CHUNKER_DELETE_FORMAT;
	const static std::string VYATTA_MODIFY_FILE;
	const static std::string CONFIG_TMP_DIR;
	const static std::string LOCAL_CHANGES_ONLY;
	const static std::string LOCAL_CONFIG_DIR;

	const static char* g_type_str[];


	static std::string
	ulltostring(unsigned long long in);

	/**
	 *
	 *
	 **/
	static int
	execute(std::string &cmd, std::string &sout, bool read = false);

	/**
	 *
	 *
	 **/
	static std::string
	mass_replace(const std::string &source, const std::string &victim, const std::string &replacement);

	/**
	 *
	 *
	 **/
	static std::string
	trim_whitespace(const std::string &src);


	/**
	 *
	 *
	 **/
	static std::string
	generate_token();

	/**
	 *
	 *
	 **/
	static int
	mkdir_p(const char *path);

	/**
	 *
	 *
	 **/
	static bool
	create_conf_modify_file(const std::string &id, const std::string &user, const std::string &tag);

	/**
	 *
	 *
	 **/
	static bool
	read_conf_modify_file(const std::string &id, std::string &user, std::string &tag);

	/**
	 *
	 *
	 **/
	static bool
	read_conf_modify_file_from_tag(const std::string &tag, std::string &user, std::string &id);


	/**
	 *
	 *
	 **/
	static std::string
	translate_rest_to_cli(CURL *handle, const std::string &rest_cmd);
};

#endif //__COMMON_HH__
