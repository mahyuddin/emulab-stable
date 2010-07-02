/*
 * EMULAB-COPYRIGHT
 * Copyright (c) 2000-2006 University of Utah and the Flux Group.
 * All rights reserved.
 */

/*
 * Determine the size of the target disk in sectors.
 */

#include <unistd.h>
#include <stdio.h>

#ifdef __FreeBSD__
#if __FreeBSD__ >= 5
#include <sys/disk.h>
#else
#include <sys/disklabel.h>
#endif
#else
#ifdef __linux__
#include <sys/ioctl.h>
#include <linux/fs.h>
#endif
#endif

unsigned long
getdisksize(int fd)
{
	unsigned long disksize = 0;
	unsigned int ssize = 512;
	off_t whuzat;

#ifdef linux
	if (disksize == 0) {
		int rv;
		rv = ioctl(fd, BLKGETSIZE, &disksize);
		if (rv < 0)
			disksize = 0;
	}
#else
#ifdef DIOCGMEDIASIZE
	if (disksize == 0) {
		int rv;
		off_t dsize;

		if (ioctl(fd, DIOCGSECTORSIZE, &ssize) < 0)
			ssize = 512;
		rv = ioctl(fd, DIOCGMEDIASIZE, &dsize);
		if (rv >= 0)
			disksize = (unsigned long)(dsize / ssize);
	}
#else
#ifdef DIOCGDINFO
	if (disksize == 0) {
		int rv;
		struct disklabel label;

		rv = ioctl(fd, DIOCGDINFO, &label);
		if (rv >= 0)
			disksize = label.d_secperunit;
	}
#endif
#endif
#endif

	whuzat = lseek(fd, (off_t)0, SEEK_CUR);

	/*
	 * OS wouldn't tell us anything directly, try a seek to the
	 * end of the device.
	 */
	if (disksize == 0) {
		off_t lastoff;

		lastoff = lseek(fd, (off_t)0, SEEK_END);
		if (lastoff > 0)
			disksize = (unsigned long)(lastoff / ssize);
	}

	/*
	 * Make sure we can seek to that sector
	 */
	if (lseek(fd, (off_t)(disksize-1) * ssize, SEEK_SET) < 0)
		fprintf(stderr, "WARNING: "
			"could not seek to final sector (%lu) of disk\n",
			disksize - 1);

	if (whuzat >= 0) {
		if (lseek(fd, whuzat, SEEK_SET) < 0)
			fprintf(stderr, "WARNING: "
				"could not seek to previous offset on disk\n");
	}

	return disksize;
}
