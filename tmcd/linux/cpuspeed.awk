#!/usr/bin/awk -f
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2003 University of Utah and the Flux Group.
# All rights reserved.
#

/^cpu MHz.*(24|25)[0-9][0-9]\.[0-9]+$/ {
    print "2500";
    next
}
/^cpu MHz.*(19|20)[0-9][0-9]\.[0-9]+$/ {
    print "2000";
    next
}
/^cpu MHz.*1[45][0-9][0-9]\.[0-9]+$/ {
    print "1500";
    next
}
/^cpu MHz.*8[0-9][0-9]\.[0-9]+$/ {
    print "850";
    next
}
/^cpu MHz.*6[0-9][0-9]\.[0-9]+$/ {
    print "600";
    next
}
/^cpu MHz.*29[0-9]|30[0-9]\.[0-9]+$/ {
    print "300";
    next
}
/^cpu MHz.*/ {
    print "0";
    next
}
