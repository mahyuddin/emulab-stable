/*
 * EMULAB-COPYRIGHT
 * Copyright (c) 2000-2002 University of Utah and the Flux Group.
 * All rights reserved.
 */

#include <sys/types.h>
#include <netinet/in.h>
#include <stdio.h>

#include "bootwhat.h"

#ifdef USE_NULL_DB

/*
 * For now, hardwired.
 */
#define NETBOOT		"/tftpboot/netboot"

int
open_bootinfo_db(void)
{
	return 0;
}

int
query_bootinfo_db(struct in_addr ipaddr, boot_what_t *info)
{
#if 0
	info->type = BIBOOTWHAT_TYPE_MB;
	info->what.mb.tftp_ip.s_addr = 0;
	strcpy(info->what.mb.filename, NETBOOT);
#else
	info->type = BIBOOTWHAT_TYPE_SYSID;
	info->what.sysid = 165; /* BSD */
#endif
	return 0;
}

int
close_bootinfo_db(void)
{
	return 0;
}
#endif
