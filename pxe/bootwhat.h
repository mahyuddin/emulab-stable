/*
 * Copyright (c) 2000, 2001, 2003, 2004 University of Utah and the Flux Group.
 * All rights reserved.
 *
 * boot/bootwhat.h from the OSKit.
 */

#ifndef _OSKIT_BOOT_BOOTWHAT_H_
#define _OSKIT_BOOT_BOOTWHAT_H_

#define BOOTWHAT_DSTPORT		6968
#define BOOTWHAT_SRCPORT		9696
#define BOOTWHAT_SENDPORT		6970

/*
 * This is the structure we pass back and forth between pxeboot on a node
 * and a server running on some other machine, that tells what to do.
 *
 * The structure below was changed, adding the version slot by splitting
 * the opcode from an int into a short. Old clients conveniently look like a
 * version zero client. The same was done for the "type" field, splitting 
 * that into "flags" and "type" shorts.
 */
#define  MAX_BOOT_DATA		512
#define  MAX_BOOT_PATH		256
#define  MAX_BOOT_CMDLINE	((MAX_BOOT_DATA - MAX_BOOT_PATH) - 32)

typedef struct {
	short   version;
	short	opcode;
	int	status;
	char	data[MAX_BOOT_DATA];
} boot_info_t;

/* Opcode */
#define BIOPCODE_BOOTWHAT_REQUEST	1	/* What to boot request */
#define BIOPCODE_BOOTWHAT_REPLY		2	/* What to boot reply */
#define BIOPCODE_BOOTWHAT_ACK		3	/* Ack to Reply */
#define BIOPCODE_BOOTWHAT_ORDER		4	/* Unsolicited command */
#define BIOPCODE_BOOTWHAT_INFO		5	/* Request for bootinfo */

/* Version */
#define BIVERSION_CURRENT		1	/* Old version is zero */

/* Status */
#define BISTAT_SUCCESS			0
#define BISTAT_FAIL			1

/* BOOTWHAT Reply */
typedef struct boot_what {
	short	flags;
	short	type;
	union {
		/*
		 * Type is BIBOOTWHAT_TYPE_PART
		 *
		 * Specifies the partition number.
		 */
		int			partition;
		
		/*
		 * Type is BIBOOTWHAT_TYPE_SYSID
		 *
		 * Specifies the PC BIOS filesystem type.
		 */
		int			sysid;
		
		/*
		 * Type is BIBOOTWHAT_TYPE_MB
		 *
		 * Specifies a multiboot kernel pathway suitable for TFTP.
		 */
		struct {
			struct in_addr	tftp_ip;
			char		filename[MAX_BOOT_PATH];
		} mb;

		/*
		 * Type is BIBOOTWHAT_TYPE_MFS
		 *
		 * Specifies network path to MFS (boss:/tftpboot/frisbee)
		 * With no host spec, defaults to bootinfo server IP.
		 */
		char			mfs[MAX_BOOT_PATH];
	} what;
	/*
	 * Kernel and command line to pass to boot loader or multiboot kernel.
	 */
	char	cmdline[1];
} boot_what_t;

/* What type of thing to boot */
#define BIBOOTWHAT_TYPE_PART	1	/* Boot a partition number */
#define BIBOOTWHAT_TYPE_SYSID	2	/* Boot a system ID */
#define BIBOOTWHAT_TYPE_MB	3	/* Boot a multiboot image */
#define BIBOOTWHAT_TYPE_WAIT    4	/* Wait, no boot until later */
#define BIBOOTWHAT_TYPE_REBOOT	5	/* Reboot */
#define BIBOOTWHAT_TYPE_AUTO	6	/* Do a bootinfo query */
#define BIBOOTWHAT_TYPE_MFS	7	/* Boot an MFS from server:/path */

/* Flags */
#define BIBOOTWHAT FLAGS_CMDLINE	0x01	/* Kernel to boot */ 

#endif /* _OSKIT_BOOT_BOOTWHAT_H_ */
