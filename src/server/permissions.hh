/**
 * Module: permissions.hh
 * This code was originally developed by Vyatta, Inc.
 * Portions created by Vyatta are Copyright (C) 2009, 2010 Vyatta, Inc.
 * All Rights Reserved.
 * Authors: John Southworth
 * Date: 2013
 * Description: permission query handler
 *
 **/

#ifndef __PERMISSIONS_HH__
#define __PERMISSIONS_HH__

#include <jansson.h>
#include <vyatta-util/map.h>
#include <string>
#include "http.hh"
#include "mode.hh"

class Permissions : protected Mode
{
public:
	Permissions(bool debug);
	~Permissions();

	void
	process(Session &session);

private: //variables
	json_t *maptojson(struct map *perms);
};





#endif //__OPMODE_HH__
