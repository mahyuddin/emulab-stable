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

package com.flack.geni.plugins.emulab
{
	import com.flack.geni.RspecUtil;
	import com.flack.geni.plugins.SliverTypeInterface;
	import com.flack.geni.plugins.SliverTypePart;
	import com.flack.geni.resources.physical.PhysicalNode;
	import com.flack.geni.resources.virtual.VirtualInterface;
	import com.flack.geni.resources.virtual.VirtualNode;
	import com.flack.geni.resources.virtual.VirtualNodeCollection;
	
	import mx.collections.ArrayCollection;
	import mx.controls.Alert;

	public class FirewallSliverType implements SliverTypeInterface
	{
		static public const TYPE_FIREWALL:String = "firewall";
		
		public var firewallStyle:String = "open";
		public var firewallType:String = "";
		
		public function FirewallSliverType()
		{
		}
		
		public function get Name():String { return TYPE_FIREWALL; }
		
		public function get namespace():Namespace
		{
			return new Namespace("firewall", "http://www.protogeni.net/resources/rspec/ext/firewall/1");
		}
		
		public function get schema():String
		{
			return "";
		}

		public function get Part():SliverTypePart { return new FirewallVgroup(); }
		
		public function get Clone():SliverTypeInterface
		{
			var clone:FirewallSliverType = new FirewallSliverType();
			clone.firewallStyle = firewallStyle;
			clone.firewallType = firewallType;
			return clone;
		}
		
		public function get SimpleList():ArrayCollection
		{
			return new ArrayCollection();
		}
		
		public function canAdd(node:VirtualNode):Boolean
		{
			// There can only be one firewall per manager
			var existingFirewall:VirtualNodeCollection = node.slice.nodes.getByManager(node.manager).getBySliverType(FirewallSliverType.TYPE_FIREWALL);
			if(existingFirewall.length > 0 && existingFirewall.collection[0] != node)
				return false;
			return true;
		}
		
		public function applyToSliverTypeXml(node:VirtualNode, xml:XML):void
		{
			var firewallConfigXml:XML = <firewall_config />;
			firewallConfigXml.setNamespace(namespace);
			firewallConfigXml.@style = firewallStyle;
			if(firewallType.length > 0)
				firewallConfigXml.@type = firewallType;
			xml.appendChild(firewallConfigXml);
		}
		
		public function applyFromAdvertisedSliverTypeXml(node:PhysicalNode, xml:XML):void
		{
			applyFromSliverTypeXml(null, xml);
		}
		
		public function applyFromSliverTypeXml(node:VirtualNode, xml:XML):void
		{
			for each(var sliverTypeChild:XML in xml.children())
			{
				if(sliverTypeChild.namespace() == namespace)
				{
					if(sliverTypeChild.localName() == "firewall_config")
					{
						firewallStyle = String(sliverTypeChild.@style);
						firewallType = String(sliverTypeChild.@type);
					}
					
				}
			}
		}
		
		public function interfaceRemoved(iface:VirtualInterface):void
		{
		}
		
		public function interfaceAdded(iface:VirtualInterface):void
		{
		}
		
		// only one per manager
	}
}