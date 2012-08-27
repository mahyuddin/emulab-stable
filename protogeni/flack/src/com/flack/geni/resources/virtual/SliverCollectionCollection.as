/* GENIPUBLIC-COPYRIGHT
* Copyright (c) 2008-2012 University of Utah and the Flux Group.
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

package com.flack.geni.resources.virtual
{
	import com.flack.geni.GeniMain;
	
	import flash.utils.Dictionary;

	public class SliverCollectionCollection
	{
		public var collection:Dictionary;
		public function SliverCollectionCollection()
		{
			collection = new Dictionary();
		}
		
		public function getOrAdd(from:Sliver):SliverCollection
		{
			var sliverCollection:SliverCollection = collection[from.manager.id.full];
			if(sliverCollection == null)
			{
				sliverCollection = new SliverCollection();
				collection[from.manager.id.full] = sliverCollection;
			}
			return sliverCollection;
		}
		
		public function add(from:Sliver, to:Sliver):void
		{
			var sliverCollection:SliverCollection = getOrAdd(from);
			if(!sliverCollection.contains(to))
				sliverCollection.add(to);
		}
		
		public function remove(from:Sliver, to:Sliver):void
		{
			var sliverCollection:SliverCollection = getOrAdd(from);
			sliverCollection.remove(to);
		}
		
		public function contains(from:Sliver, to:Sliver):Boolean
		{
			var sliverCollection:SliverCollection = getOrAdd(from);
			return sliverCollection.contains(to);
		}
		
		public function get numDependencies():int
		{
			var length:int = 0;
			for(var managerId:String in collection)
			{
				length += collection[managerId].length;
			}
			return length;
		}
		
		public function getLinearized(slice:Slice):SliverCollection
		{
			var searchSlivers:SliverCollection = new SliverCollection();
			var orderedSlivers:SliverCollection = new SliverCollection();
			for(var managerId:String in collection)
				searchSlivers.add(slice.slivers.getByManager(GeniMain.geniUniverse.managers.getById(managerId)));
			while(searchSlivers.length > 0)
				search(searchSlivers.collection[0], searchSlivers, orderedSlivers);
			return orderedSlivers;
		}
		
		private function search(sliver:Sliver, searchSlivers:SliverCollection, orderedSlivers:SliverCollection):void
		{
			var connectedSlivers:SliverCollection = collection[sliver.manager.id.full];
			for each(var connectedSliver:Sliver in connectedSlivers.collection)
			{
				if(searchSlivers.contains(connectedSliver))
					search(connectedSliver, searchSlivers, orderedSlivers);
			}
			orderedSlivers.add(sliver);
			searchSlivers.remove(sliver);
		}
	}
}