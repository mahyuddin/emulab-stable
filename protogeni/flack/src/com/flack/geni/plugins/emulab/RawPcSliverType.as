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
	import com.flack.geni.plugins.SliverTypeInterface;
	import com.flack.geni.plugins.SliverTypePart;
	import com.flack.geni.resources.physical.PhysicalNode;
	import com.flack.geni.resources.virtual.VirtualInterface;
	import com.flack.geni.resources.virtual.VirtualNode;
	
	import mx.collections.ArrayCollection;
	
	public class RawPcSliverType implements SliverTypeInterface
	{
		static public const TYPE_RAWPC_V1:String = "raw";
		static public const TYPE_RAWPC_V2:String = "raw-pc";
		
		public function RawPcSliverType()
		{
		}
		
		public function get Name():String { return TYPE_RAWPC_V2; }
		
		public function get namespace():Namespace
		{
			return null;
		}
		
		public function get schema():String
		{
			return "";
		}
		
		public function get Part():SliverTypePart
		{
			return null;
		}
		
		public function get Clone():SliverTypeInterface
		{
			var clone:RawPcSliverType = new RawPcSliverType();
			return clone;
		}
		
		public function applyToSliverTypeXml(node:VirtualNode, xml:XML):void
		{
		}
		
		public function applyFromAdvertisedSliverTypeXml(node:PhysicalNode, xml:XML):void
		{
		}
		
		public function applyFromSliverTypeXml(node:VirtualNode, xml:XML):void
		{
		}
		
		public function interfaceRemoved(iface:VirtualInterface):void
		{
		}
		
		public function interfaceAdded(iface:VirtualInterface):void
		{
		}
		
		public function canAdd(node:VirtualNode):Boolean
		{
			return true;
		}
		
		public function get SimpleList():ArrayCollection
		{
			return null;
		}
	}
}