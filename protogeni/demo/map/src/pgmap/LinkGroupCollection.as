/* GENIPUBLIC-COPYRIGHT
 * Copyright (c) 2009 University of Utah and the Flux Group.
 * All rights reserved.
 *
 * Permission to use, copy, modify and distribute this software is hereby
 * granted provided that (1) source code retains these copyright, permission,
 * and disclaimer notices, and (2) redistributions including binaries
 * reproduce the notices in supporting documentation.
 *
 * THE UNIVERSITY OF UTAH ALLOWS FREE USE OF THIS SOFTWARE IN ITS "AS IS"
 * CONDITION.  THE UNIVERSITY OF UTAH DISCLAIMS ANY LIABILITY OF ANY KIND
 * FOR ANY DAMAGES WHATSOEVER RESULTING FROM THE USE OF THIS SOFTWARE.
 */
 
 package pgmap
{
	import mx.collections.ArrayCollection;
	
	public class LinkGroupCollection
	{
		public function LinkGroupCollection()
		{
		}
		
		public var collection:ArrayCollection = new ArrayCollection();

		public function Get(lat1:Number, lng1:Number, lat2:Number, lng2:Number):LinkGroup {
			for each(var g:LinkGroup in collection) {
				if(g.latitude1 == lat1 && g.longitude1 == lng1) {
					if(g.latitude2 == lat2 && g.longitude2 == lng2) {
						return g;
					}
				}
				if(g.latitude1 == lat2 && g.longitude1 == lng2) {
					if(g.latitude2 == lat1 && g.longitude2 == lng1) {
						return g;
					}
				}
			}
			return null;
		}
		
		public function Add(g:LinkGroup):void {
			collection.addItem(g);
		}
	}
}