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

package com.flack.geni.resources.sites
{
	import com.flack.geni.resources.SliverTypeCollection;
	import com.flack.geni.resources.physical.PhysicalLink;
	import com.flack.geni.resources.physical.PhysicalLinkCollection;
	import com.flack.geni.resources.physical.PhysicalLocationCollection;
	import com.flack.geni.resources.physical.PhysicalNode;
	import com.flack.geni.resources.physical.PhysicalNodeCollection;
	import com.flack.shared.resources.docs.RspecVersion;
	import com.flack.shared.resources.docs.RspecVersionCollection;
	import com.flack.shared.resources.sites.ApiDetails;
	import com.flack.shared.resources.sites.FlackManager;
	
	/**
	 * Manager within the GENI world
	 * 
	 * @author mstrum
	 * 
	 */
	public class GeniManager extends FlackManager
	{
		public static const ALLOCATE_SINGLE:String = "geni_single";
		public static const ALLOCATE_DISJOINT:String = "geni_disjoint";
		public static const ALLOCATE_MANY:String = "geni_many";
				
		// Advertised Resources
		[Bindable]
		public var nodes:PhysicalNodeCollection;
		[Bindable]
		public var links:PhysicalLinkCollection;
		
		// Support Information
		public var inputRspecVersions:RspecVersionCollection = new RspecVersionCollection();
		[Bindable]
		public var inputRspecVersion:RspecVersion = null;
		
		public var outputRspecVersions:RspecVersionCollection = new RspecVersionCollection();
		[Bindable]
		public var outputRspecVersion:RspecVersion = null;
		
		public var supportedSliverTypes:SupportedSliverTypeCollection = new SupportedSliverTypeCollection();
		public var supportedLinkTypes:SupportedLinkTypeCollection = new SupportedLinkTypeCollection();
		public function get SupportsLinks():Boolean
		{
			return supportedLinkTypes.length > 0;
		}
		
		public var locations:PhysicalLocationCollection;
		
		public var sharedVlans:Vector.<String> = null;
		
		public var singleAllocation:Boolean = false;
		public var allocate:String = ALLOCATE_SINGLE;
		public var bestEffort:Boolean = false;
		
		/**
		 * 
		 * @param newType Type
		 * @param newApi API type
		 * @param newId IDN-URN
		 * @param newHrn Human-readable name
		 * 
		 */
		public function GeniManager(newType:int = TYPE_OTHER,
									newApi:int = ApiDetails.API_GENIAM,
									newId:String = "",
									newHrn:String = "")
		{
			super(
				newType,
				newApi,
				newId,
				newHrn
			);
			
			resetComponents();
		}
		
		/**
		 * Clears components, the advertisement, status, and error details
		 * 
		 */
		override public function clear():void
		{
			resetComponents();
			super.clear();
		}
		
		/**
		 * Clears nodes, links, sliver types, and locations
		 * 
		 */
		public function resetComponents():void
		{
			nodes = new PhysicalNodeCollection();
			links = new PhysicalLinkCollection();
			//supportedSliverTypes = new SupportedSliverTypeCollection();
			//supportedLinkTypes = new SupportedLinkTypeCollection();
			locations = new PhysicalLocationCollection();
		}
		
		/**
		 * 
		 * @param findId Component ID
		 * @return Component matching the ID
		 * 
		 */
		public function getById(findId:String):*
		{
			var component:* = nodes.getById(findId);
			if(component != null)
				return component;
			return nodes.getInterfaceById(findId);
		}
		
		override public function toString():String
		{
			var result:String = "[GeniManager ID=" + id.full
				+ ", Url=" + url
				+ ", Hrn=" + hrn
				+ ", Type=" + type
				+ ", Api=" + api.type
				+ ", Status=" + Status + "]\n";
			if(nodes.length > 0)
			{
				result += "\t[Nodes]\n";
				for each(var node:PhysicalNode in nodes.collection)
					result += node.toString();
				result += "\t[/Nodes]\n";
			}
			if(links.length > 0)
			{
				result += "\t[Links]\n";
				for each(var link:PhysicalLink in links.collection)
					result += link.toString();
				result += "\t[/Links]\n";
			}
			return result += "[/GeniManager]";
		}
	}
}