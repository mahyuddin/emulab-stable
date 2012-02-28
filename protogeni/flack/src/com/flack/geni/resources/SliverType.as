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

package com.flack.geni.resources
{
	import com.flack.geni.resources.physical.DiskImageCollection;
	import com.flack.geni.resources.virtual.PipeCollection;

	/**
	 * Describes the sliver environment which will be given to the user
	 * 
	 * @author mstrum
	 * 
	 */
	public class SliverType
	{
		[Bindable]
		public var name:String;
		public var extensions:Extensions = new Extensions();
		
		// Advertised
		// Standard
		public var diskImages:DiskImageCollection = new DiskImageCollection();
		// Planetlab
		public var planetLabInitscripts:Vector.<String> = null;
		
		// Requestables
		// Standard
		[Bindable]
		public var selectedImage:DiskImage = null;
		// Planetlab
		public var selectedPlanetLabInitscript:String = "";
		// Firewall
		public var firewallStyle:String = "open";
		public var firewallType:String = "";
		// Delay
		public var pipes:PipeCollection = null;
		
		/**
		 * 
		 * @param newName Name of the sliver type
		 * 
		 */
		public function SliverType(newName:String = "")
		{
			name = newName;
		}
		
		public function toString():String
		{
			var result:String = "[SliverType Name="+name+"]\n";
			if(diskImages.length > 0)
			{
				result += "\t[DiskImages]\n";
				for each(var diskImage:DiskImage in diskImages.collection)
					result += "\t\t" + diskImage.toString() + "\n";
				result += "\t[/DiskImages]\n";
			}
			
			return result += "[/SliverType]\n";
		}
	}
}