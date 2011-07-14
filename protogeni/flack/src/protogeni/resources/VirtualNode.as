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
	import mx.collections.XMLListCollection;

	/**
	 * Resource within a slice
	 * 
	 * @author mstrum
	 * 
	 */
	public class VirtualNode extends VirtualComponent
	{
		[Bindable]
		public var physicalNode:PhysicalNode;
		public var _exclusive:Boolean;
		public var superNode:VirtualNode;
		public var subNodes:VirtualNodeCollection = new VirtualNodeCollection();
		
		[Bindable]
		public var sliver:Sliver;
		
		[Bindable]
		public var interfaces:VirtualInterfaceCollection;
		
		public var pipes:PipeCollection;
		
		public var flackX:int = -1;
		public var flackY:int = -1;
		public var flackUnbound:Boolean = false;
		
		public var sliverType:String = "";
		
		public var installServices:Vector.<InstallService> = new Vector.<InstallService>();
		public var executeServices:Vector.<ExecuteService> = new Vector.<ExecuteService>();
		public var loginServices:Vector.<LoginService> = new Vector.<LoginService>();
		
		[Bindable]
		public var diskImage:String = "";
		
		public function get isDelayNode():Boolean { return this.sliverType == "delay" };
		public function set isDelayNode(value:Boolean):void {
			if(value) {
				this._exclusive = true;
				this.sliverType = "delay";
			} else {
				Exclusive = this.Exclusive;
			}
		}
		
		// Extensions
		public var extensionsNodes:XMLListCollection = new XMLListCollection();
		
		public var manager:GeniManager;
		
		// Depreciated
		public var virtualizationType:String = "emulab-vnode";
		public var virtualizationSubtype:String = "emulab-openvz";
		
		public function VirtualNode(owner:Sliver)
		{
			super();
			
			this.sliver = owner;
			if(owner != null)
				manager = owner.manager;
			
			this.interfaces = new VirtualInterfaceCollection();
			this.pipes = new PipeCollection();
			// depreciated for v2
			var controlInterface:VirtualInterface = new VirtualInterface(this);
			controlInterface.id = "control";
			this.interfaces.add(controlInterface);
		}
		
		public function get Exclusive():Boolean {
			return this._exclusive;
		}
		
		public function set Exclusive(value:Boolean):void {
			this._exclusive = value;

			if(this.physicalNode != null
					&& this.physicalNode.sliverTypes.length == 1
					&& this.physicalNode.sliverTypes[0].name != "N/A")
				this.sliverType = this.physicalNode.sliverTypes[0].name;
			else {
				if(this.manager is ProtogeniComponentManager) {
					if(this._exclusive)
						sliverType = "raw-pc";
					else
						sliverType = "emulab-openvz";
				} else if(this.manager is PlanetlabAggregateManager) {
					sliverType = "plab-vnode";
				}
			}
			
		}
		
		public function setToPhysicalNode(node:PhysicalNode):void
		{
			this.physicalNode = node;
			this.clientId = node.name;
			this.manager = node.manager;
			this.sliverId = node.id;
			this.Exclusive = node.exclusive;
		}
		
		public function setDiskImage(img:String):void
		{
			if(img != null && img.length > 0)
			{
				if(img.length > 3 && img.substr(0, 3) == "urn")
					this.diskImage = img;
				else
					this.diskImage = DiskImage.getDiskImageLong(img, this.manager);
			} else
				this.diskImage = "";
			
		}
		
		public function allocateInterface():VirtualInterface
		{
			if(!IsBound())
			{
				var newVirtualInterface:VirtualInterface = new VirtualInterface(this);
				newVirtualInterface.id = this.clientId + ":if" + this.interfaces.length;
				//newVirtualInterface.role = PhysicalNodeInterface.ROLE_EXPERIMENTAL;
				newVirtualInterface.capacity = 100000;
				//newVirtualInterface.isVirtual = true;
				return newVirtualInterface;
			} else {
				for each (var candidate:PhysicalNodeInterface in physicalNode.interfaces.collection)
				{
					if (candidate.role == PhysicalNodeInterface.ROLE_EXPERIMENTAL)
					{
						var success:Boolean = true;
						for each (var check:VirtualInterface in interfaces.collection)
						{
							if(check.IsBound()
									&& check.physicalNodeInterface == candidate)
								success = false;
							break;
						}
						if(success)
						{
							var newPhysicalInterface:VirtualInterface = new VirtualInterface(this);
							newPhysicalInterface.physicalNodeInterface = candidate;
							newPhysicalInterface.id = this.clientId + ":if" + this.interfaces.collection.length;
							return newPhysicalInterface;
						}
					}
				}
			}
			return null;
		}
		
		public function IsBound():Boolean {
			return physicalNode != null;
		}
		
		// Gets all connected physical nodes
		public function GetPhysicalNodes():Vector.<PhysicalNode> {
			var ac:Vector.<PhysicalNode> = new Vector.<PhysicalNode>();
			for each(var nodeInterface:VirtualInterface in this.interfaces.collection) {
				for each(var nodeLink:VirtualLink in nodeInterface.virtualLinks.collection) {
					for each(var nodeLinkInterface:VirtualInterface in nodeLink.interfaces.collection)
					{
						if(nodeLinkInterface != nodeInterface
								&& ac.indexOf(nodeLinkInterface.owner.physicalNode) == -1)
							ac.push(nodeLinkInterface.owner.physicalNode);
					}
				}
			}
			return ac;
		}
		
		public function GetAllNodes():VirtualNodeCollection {
			var ac:VirtualNodeCollection = new VirtualNodeCollection();
			for each(var sourceInterface:VirtualInterface in this.interfaces.collection) {
				for each(var virtualLink:VirtualLink in sourceInterface.virtualLinks.collection) {
					for each(var destInterface:VirtualInterface in virtualLink.interfaces.collection) {
						if(destInterface.owner != this
								&& !ac.contains(destInterface.owner))
							ac.add(destInterface.owner);
					}
				}
			}
			return ac;
		}
		
		// Gets all virtual links connected to this node
		public function GetLinksForPhysical(n:PhysicalNode):VirtualLinkCollection {
			var ac:VirtualLinkCollection = new VirtualLinkCollection();
			
			for each(var i:VirtualInterface in this.interfaces.collection) {
				for each(var l:VirtualLink in i.virtualLinks.collection) {
					for each(var nl:VirtualInterface in l.interfaces.collection) {
						if(nl != i
								&& nl.owner.physicalNode == n
								&& !ac.contains(l)) {
							ac.add(l);
						}
					}
				}
			}
			return ac;
		}
		
		public function GetLinks(n:VirtualNode):VirtualLinkCollection {
			var ac:VirtualLinkCollection = new VirtualLinkCollection();
			
			for each(var i:VirtualInterface in this.interfaces.collection) {
				for each(var l:VirtualLink in i.virtualLinks.collection) {
					for each(var nl:VirtualInterface in l.interfaces.collection) {
						if(nl != i
								&& nl.owner == n
								&& !ac.contains(l)) {
							ac.add(l);
						}
					}
				}
			}
			return ac;
		}
	}
}