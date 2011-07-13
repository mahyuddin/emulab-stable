/* GENIPUBLIC-COPYRIGHT
* Copyright (c) 2008-2011 University of Utah and the Flux Group.
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

package protogeni.resources
{
	/**
	 * Link between resources within a slice
	 * 
	 * @author mstrum
	 * 
	 */
	public class VirtualLink extends VirtualComponent
	{
		public static const TYPE_NORMAL:int = 0;
		public static const TYPE_TUNNEL:int = 1;
		public static const TYPE_ION:int = 2;
		public static const TYPE_GPENI:int = 3;
		public static function TypeToString(type:int):String {
			switch(type){
				case TYPE_NORMAL: return "LAN";
				case TYPE_TUNNEL: return "Tunnel";
				case TYPE_ION: return "ION";
				case TYPE_GPENI: return "GPENI";
			}
			return "Unknown";
		}
		
		[Bindable]
		public var type:String;
		[Bindable]
		public var interfaces:VirtualInterfaceCollection = new VirtualInterfaceCollection();
		
		public var linkType:int = TYPE_NORMAL;
		
		[Bindable]
		public var capacity:Number;
		
		public var vlantag:String = "";
		
		public function VirtualLink(owner:Sliver = null)
		{
			super(owner);
		}
		
		public function establish(first:VirtualNode, second:VirtualNode):Boolean
		{
			var firstInterface:VirtualInterface = first.allocateInterface();
			var secondInterface:VirtualInterface = second.allocateInterface();
			if(firstInterface == null || secondInterface == null)
				return false;
			this.clientId = slivers.collection[0].slice.slivers.getUniqueVirtualLinkId(this);
			first.interfaces.add(firstInterface);
			second.interfaces.add(secondInterface);
			firstInterface.virtualLinks.add(this);
			secondInterface.virtualLinks.add(this);
			this.interfaces.add(firstInterface);
			this.interfaces.add(secondInterface);
			
			if(first.manager == second.manager)
				this.linkType = TYPE_NORMAL;
			else
			{
				/*if(first.manager.supportsIon && second.manager.supportsIon && Main.useIon)
					this.linkType = TYPE_ION;
				else if (first.manager.supportsGpeni && second.manager.supportsGpeni && Main.useGpeni)
					this.linkType = TYPE_GPENI;
				else*/
					this.setUpTunnels();
				
				// Make sure nodes are in both
				if(!second.slivers.collection[0].nodes.contains(first))
					second.slivers.collection[0].nodes.add(first);
				if(!first.slivers.collection[0].nodes.contains(second))
					first.slivers.collection[0].nodes.add(second);
				
				// Add relative slivers
				if(this.slivers.collection[0].manager != first.slivers.collection[0].manager)
					this.slivers.add(first.slivers.collection[0]);
				else if(this.slivers.collection[0].manager != second.slivers.collection[0].manager)
					this.slivers.add(second.slivers.collection[0]);
			}
			
			for each(var s:Sliver in this.slivers.collection)
				s.links.add(this);
			
				this.capacity = Math.floor(Math.min(firstInterface.capacity,
													secondInterface.capacity));
			if (first.clientId.slice(0, 2) == "pg"
					|| second.clientId.slice(0, 2) == "pg")
				this.capacity = 1000000;
			if(this.linkType == TYPE_GPENI
					|| this.linkType == TYPE_ION)
				this.capacity = 100000;
			
			return true;
		}
		
		public function setUpTunnels():void
		{
			this.linkType = VirtualLink.TYPE_TUNNEL;
			this.type = "gre-tunnel";
			for each(var i:VirtualInterface in this.interfaces.collection) {
				if(i.ip.length == 0) {
					i.ip = VirtualInterface.getNextTunnel();
					i.netmask = "255.255.255.0";
					i.type = "ipv4";
				}
			}
		}
		
		public function remove():void
		{
			for each(var vi:VirtualInterface in this.interfaces.collection)
			{
				if(vi.id != "control")
					vi.owner.interfaces.remove(vi);
				
				for(var i:int = 1; i < vi.owner.slivers.length; i++)
				{
					if(vi.owner.slivers.collection[i].links.getForNode(vi.owner).length == 0)
						vi.owner.slivers.collection[i].nodes.remove(vi.owner);
				}
			}
			this.interfaces = new VirtualInterfaceCollection();
			for each(var s:Sliver in this.slivers.collection)
				s.links.remove(this);
		}
		
		public function isConnectedTo(target:GeniManager):Boolean
		{
			for each(var i:VirtualInterface in this.interfaces.collection)
			{
				if(i.owner.manager == target)
					return true;
			}
			return false;
		}
		
		public function hasVirtualNode(node:VirtualNode):Boolean
		{
			for each(var i:VirtualInterface in this.interfaces.collection)
			{
				if(i.owner == node)
					return true;
			}
			
			return false;
		}
		
		public function hasPhysicalNode(node:PhysicalNode):Boolean
		{
			for each(var i:VirtualInterface in this.interfaces.collection)
			{
				if(i.owner.IsBound()
						&& i.owner.physicalNode == node)
					return true;
			}
			return false;
		}
		
		public function supportsIon():Boolean {
			for each(var i:VirtualInterface in this.interfaces.collection)
			{
				if(!i.owner.manager.supportsIon)
					return false;
			}
			return true;
		}
		
		public function supportsGpeni():Boolean {
			for each(var i:VirtualInterface in this.interfaces.collection)
			{
				if(!i.owner.manager.supportsGpeni)
					return false;
			}
			return true;
		}
	}
}