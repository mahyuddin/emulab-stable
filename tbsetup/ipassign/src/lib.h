// lib.h

/*
 * EMULAB-COPYRIGHT
 * Copyright (c) 2003 University of Utah and the Flux Group.
 * All rights reserved.
 */

// project-wide inclusions and declarations go here.

#ifndef LIB_H_IP_ASSIGN_1
#define LIB_H_IP_ASSIGN_1

#include <iostream>
#include <iomanip>
#include <vector>
#include <list>
#include <map>
#include <set>
#include <sstream>
#include <cmath>
#include <cstdio>
#include <algorithm>
#include <bitset>
#include <memory>
#include <climits>
#include <queue>

extern "C"
{
#include <metis.h>
}

#include "Exception.h"
#include "bitmath.h"

extern const int totalBits;
extern const int prefixBits;
extern const int postfixBits;
extern const IPAddress prefix;
extern const IPAddress prefixMask;
extern const IPAddress postfixMask;

#endif

