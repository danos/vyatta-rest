/*
 * Copyright (c) 2017-2019, AT&T Intellectual Property.  All rights reserved.
 * Copyright (c) 2013 by Brocade Communications Systems, Inc.
 * All rights reserved.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

#ifndef DEBUG_H_
#define DEBUG_H_

#include <stdarg.h>
#include <stdio.h>
#include <syslog.h>

#ifdef __cplusplus
extern "C" {
#endif

void dsyslog_(const char *fmt, ...) __attribute__ ((format (printf, 1, 2)));

inline void dsyslog_(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vsyslog(LOG_DEBUG, fmt, ap);
	va_end(ap);
}

#define dsyslog(cond, fmt, ...) if (cond) dsyslog_(fmt, ##__VA_ARGS__)

#ifdef __cplusplus
}
#endif

#endif
