#!/usr/bin/awk -f
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2003 University of Utah and the Flux Group.
# All rights reserved.
#

/^CPU:.*\((25)[0-9][0-9]\.[0-9]+\-MHz/ {
    print "2500";
    next
}
/^CPU:.*\((19|20)[0-9][0-9]\.[0-9]+\-MHz/ {
    print "2000";
    next
}
/^CPU:.*\(1[45][0-9][0-9]\.[0-9]+\-MHz/ {
    print "1500";
    next
}
/^CPU:.*\(8[0-9][0-9]\.[0-9]+\-MHz/ {
    print "850";
    next
}
/^CPU:.*\(6[0-9][0-9]\.[0-9]+\-MHz/ {
    print "600";
    next
}
/^CPU:.*\(29[0-9]|30[0-9]\.[0-9]+\-MHz/ {
    print "300";
    next
}
/^CPU:.*/ {
    print "0";
    next
}
