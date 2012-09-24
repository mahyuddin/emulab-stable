/*
 * Copyright (c) 2002-2010 University of Utah and the Flux Group.
 * 
 * {{{EMULAB-LICENSE
 * 
 * This file is part of the Emulab network testbed software.
 * 
 * This file is free software: you can redistribute it and/or modify it
 * under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or (at
 * your option) any later version.
 * 
 * This file is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Affero General Public
 * License for more details.
 * 
 * You should have received a copy of the GNU Affero General Public License
 * along with this file.  If not, see <http://www.gnu.org/licenses/>.
 * 
 * }}}
 */

// This file may need to be changed depending on the architecture.
#ifndef __PORT_H
#define __PORT_H
#include <limits.h>

#ifndef WCHAR_MIN
#define WCHAR_MIN INT_MIN
#define WCHAR_MAX INT_MAX
#endif

/*
 * We have to do these includes differently depending on which version of gcc
 * we're compiling with
 *
 * In G++ 4.3, hash_set and hash_map were formally deprecated and
 * moved from ext/ to backward/.  Well, that's what the release notes
 * claim.  In fact, on my system, hash_set and hash_map appear in both
 * ext/ and backward/.  But, hash_fun.h is only in backward/, necessi-
 * tating the NEWER_GCC macro.
 *
 * The real fix is to replace
 *   hash_set with tr1::unordered_set in <tr1/unordered_set>
 *   hash_map with tr1::unordered_map in <tr1/unordered_map>
 */
#if (__GNUC__ == 3 && __GNUC_MINOR__ > 0) || (__GNUC__ > 3)
#define NEW_GCC
#endif

#if (__GNUC__ == 4 && __GNUC_MINOR__ >= 3) || (__GNUC__ > 4)
#define NEWER_GCC
#endif

#ifdef NEW_GCC
#include <ext/slist>
using namespace __gnu_cxx;
#else
#include <slist>
#endif

#ifdef NEWER_BOOST
#define BOOST_PMAP_HEADER <boost/property_map/property_map.hpp>
#else
#define BOOST_PMAP_HEADER <boost/property_map.hpp>
#endif

#else
#endif
