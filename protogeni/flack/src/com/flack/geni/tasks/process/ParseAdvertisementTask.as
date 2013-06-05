/* 
 * Copyright (c) 2008-2012 University of Utah and the Flux Group.
 * 
 * {{{GENIPUBLIC-LICENSE
 * 
 * GENI Public License
 * 
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and/or hardware specification (the "Work") to
 * deal in the Work without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Work, and to permit persons to whom the Work
 * is furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Work.
 * 
 * THE WORK IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE WORK OR THE USE OR OTHER DEALINGS
 * IN THE WORK.
 * 
 * }}}
 */

package com.flack.geni.tasks.process
{
	import com.flack.geni.RspecUtil;
	import com.flack.geni.plugins.RspecProcessInterface;
	import com.flack.geni.plugins.emulab.EmulabBbgSliverType;
	import com.flack.geni.plugins.emulab.EmulabOpenVzSliverType;
	import com.flack.geni.plugins.emulab.EmulabXenSliverType;	
	import com.flack.geni.plugins.emulab.EmulabSppSliverType;
	import com.flack.geni.plugins.emulab.Netfpga2SliverType;
	import com.flack.geni.plugins.emulab.RawPcSliverType;
	import com.flack.geni.plugins.shadownet.JuniperRouterSliverType;
	import com.flack.geni.resources.DiskImage;
	import com.flack.geni.resources.Property;
	import com.flack.geni.resources.SliverType;
	import com.flack.geni.resources.SliverTypes;
	import com.flack.geni.resources.physical.HardwareType;
	import com.flack.geni.resources.physical.PhysicalInterface;
	import com.flack.geni.resources.physical.PhysicalLink;
	import com.flack.geni.resources.physical.PhysicalLocation;
	import com.flack.geni.resources.physical.PhysicalNode;
	import com.flack.geni.resources.sites.GeniManager;
	import com.flack.geni.resources.sites.SupportedSliverType;
	import com.flack.shared.FlackEvent;
	import com.flack.shared.SharedMain;
	import com.flack.shared.logging.LogMessage;
	import com.flack.shared.resources.IdnUrn;
	import com.flack.shared.resources.docs.Rspec;
	import com.flack.shared.resources.docs.RspecVersion;
	import com.flack.shared.resources.sites.FlackManager;
	import com.flack.shared.tasks.Task;
	import com.flack.shared.tasks.TaskError;
	import com.flack.shared.utils.DateUtil;
	
	import flash.events.Event;
	import flash.system.System;
	import flash.utils.Dictionary;
	
	import mx.core.FlexGlobals;
	
	/**
	 * Parses the manager's advertisement into itself
	 * 
	 * @author mstrum
	 * 
	 */
	public class ParseAdvertisementTask extends Task
	{
		public var manager:GeniManager;
		
		/**
		 * 
		 * @param newManager Manager to parse the advertisement
		 * 
		 */
		public function ParseAdvertisementTask(newManager:GeniManager)
		{
			super(
				"Process advertisement for " + newManager.hrn,
				"Processes the advertisement RSPEC of " + newManager.hrn,
				"Process advertisement",
				null,
				0,
				0,
				false,
				[newManager]
			);
			manager = newManager;
		}
		
		private static var NODE_PARSE : int = 0;
		private static var LINK_PARSE : int = 1;
		private static var DONE : int = 2;
		
		private var myIndex:int;
		private var myState:int = NODE_PARSE;
		private var nodes:XMLList;
		private var links:XMLList;
		private var interfaceDictionary:Dictionary;
		private var nodeNameDictionary:Dictionary;
		private var subnodeList:Array
		private var linkDictionary:Dictionary;
		private var hasslot:Boolean = false;
		
		private var skippedNodes:int;
		private var skippedLinks:int;
		
		private var defaultNamespace:Namespace;
		
		private var xmlDocument:XML = null;
		
		override protected function runStart():void
		{
			manager.resetComponents();
			
			if(manager.advertisement.document == null || manager.advertisement.document.length == 0)
			{
				addMessage(
					"No resources found",
					"Empty document, no resources added",
					LogMessage.LEVEL_WARNING
				);
				manager.Status = FlackManager.STATUS_VALID;
				SharedMain.sharedDispatcher.dispatchChanged(
					FlackEvent.CHANGED_MANAGER,
					manager,
					FlackEvent.ACTION_STATUS
				);
				SharedMain.sharedDispatcher.dispatchChanged(
					FlackEvent.CHANGED_MANAGER,
					manager,
					FlackEvent.ACTION_POPULATED
				);
				afterComplete(false);
				return;
			}
			
			try
			{
				xmlDocument = new XML(manager.advertisement.document);
			}
			catch(e:Error)
			{
				addMessage("Bad XML", "Problem creating XML from advertisement", LogMessage.LEVEL_WARNING);
				manager.Status = FlackManager.STATUS_VALID;
				SharedMain.sharedDispatcher.dispatchChanged(
					FlackEvent.CHANGED_MANAGER,
					manager,
					FlackEvent.ACTION_STATUS
				);
				SharedMain.sharedDispatcher.dispatchChanged(
					FlackEvent.CHANGED_MANAGER,
					manager,
					FlackEvent.ACTION_POPULATED
				);
				afterComplete(false);
				return;
			}
			
			if(xmlDocument.namespace() == null)
			{
				addMessage("No namespace found", "No namespace, unable to parse", LogMessage.LEVEL_WARNING);
				manager.Status = FlackManager.STATUS_VALID;
				SharedMain.sharedDispatcher.dispatchChanged(
					FlackEvent.CHANGED_MANAGER,
					manager,
					FlackEvent.ACTION_STATUS
				);
				SharedMain.sharedDispatcher.dispatchChanged(
					FlackEvent.CHANGED_MANAGER,
					manager,
					FlackEvent.ACTION_POPULATED
				);
				afterComplete(false);
				return;
			}
			
			defaultNamespace = xmlDocument.namespace();
			
			switch(defaultNamespace.uri)
			{
				case RspecUtil.rspec01Namespace:
					manager.advertisement.info =
						new RspecVersion(
							RspecVersion.TYPE_PROTOGENI,
							0.1
						);
					break;
				case RspecUtil.rspec02Namespace:
					manager.advertisement.info =
						new RspecVersion(
							RspecVersion.TYPE_PROTOGENI,
							0.2
						);
					break;
				case RspecUtil.rspec2Namespace:
					manager.advertisement.info =
						new RspecVersion(
							RspecVersion.TYPE_PROTOGENI,
							2
						);
					break;
				case RspecUtil.rspec3Namespace:
					manager.advertisement.info =
					new RspecVersion(
						RspecVersion.TYPE_GENI,
						3
					);
					break;
				default:
					afterError(
						new TaskError(
							"Namespace not supported. Advertisement RSPEC with the namespace '"
							+defaultNamespace.uri+ "' is not supported.",
							TaskError.CODE_PROBLEM
						)
					);
					return;
			}
			
			if(
				xmlDocument.@type.length() != 1 ||
				String(xmlDocument.@type) != "advertisement")
			{
				afterError(
					new TaskError(
						"Not declared an advertisement.",
						TaskError.CODE_PROBLEM
					)
				);
				return;
			}
			else
				manager.advertisement.type = Rspec.TYPE_ADVERTISEMENT;
			
			if(xmlDocument.@valid_until.length() == 1)
				manager.advertisement.expires =
					DateUtil.parseRFC3339(
						String(xmlDocument.@valid_until)
					);
			if(xmlDocument.@expires.length() == 1)
				manager.advertisement.expires =
					DateUtil.parseRFC3339(
						String(xmlDocument.@expires)
					);
			if(xmlDocument.@generated.length() == 1)
				manager.advertisement.generated =
					DateUtil.parseRFC3339(
						String(xmlDocument.@generated)
					);
			
			myState = NODE_PARSE;
			nodes = xmlDocument.defaultNamespace::node;
			links = xmlDocument.defaultNamespace::link;
			
			skippedNodes = 0;
			skippedLinks = 0;
			myIndex = 0;
			
			interfaceDictionary = new Dictionary();
			nodeNameDictionary = new Dictionary();
			subnodeList = [];
			
			FlexGlobals.topLevelApplication.stage.addEventListener(
				Event.ENTER_FRAME, parseNext
			);
		}
		
		private function parseNext(event:Event) : void
		{
			var startTime:Date = new Date();
			if (myState == NODE_PARSE)	    	
				parseNextNode();
			else if (myState == LINK_PARSE)
				parseNextLink();
			else
			{
				defaultNamespace = null;
				nodes = null;
				links = null;
				interfaceDictionary = null;
				nodeNameDictionary = null;
				subnodeList = null;
				linkDictionary = null;
				
				FlexGlobals.topLevelApplication.stage.removeEventListener(
					Event.ENTER_FRAME, parseNext
				);
				
				// Get shared VLANs
				var vlanNamepace:Namespace = RspecUtil.sharedVlanNamespace;
				var sharedVlans:XMLList = xmlDocument.vlanNamepace::rspec_shared_vlan;
				if(sharedVlans != null && sharedVlans.length() == 1)
				{
					manager.sharedVlans = new Vector.<String>();
					var available:XMLList = sharedVlans.vlanNamepace::available;
					for each(var sharedVlan:XML in available)
					{
						manager.sharedVlans.push(sharedVlan.@name);
					}
				}
				else
				{
					manager.sharedVlans = null;
				}
				
				if (myState == DONE)
				{
					// Show warning if anything was skipped
					var msgLevel:int = 
						(skippedNodes > 0 || skippedLinks > 0)
						? msgLevel = LogMessage.LEVEL_WARNING : LogMessage.LEVEL_INFO;
					addMessage(
						"Parsed",
						 manager.advertisement.info.toString() +
							"\nNodes parsed: " + manager.nodes.length +
							"\nNodes skipped: " + skippedNodes +
							"\nLinks parsed: " + manager.links.length +
							"\nLinks skipped: " + skippedLinks +
							"\n\n" /*+ manager.toString()*/,
						msgLevel,
						LogMessage.IMPORTANCE_HIGH
					);
					
					manager.Status = FlackManager.STATUS_VALID;
					SharedMain.sharedDispatcher.dispatchChanged(
						FlackEvent.CHANGED_MANAGER,
						manager,
						FlackEvent.ACTION_STATUS
					);
					SharedMain.sharedDispatcher.dispatchChanged(
						FlackEvent.CHANGED_MANAGER,
						manager,
						FlackEvent.ACTION_POPULATED
					);
					
					afterComplete(false);
				}
				else
				{
					afterError(
						new TaskError(
							"Problem parsing RSPEC",
							TaskError.CODE_UNEXPECTED
						)
					);
				}
			}
		}
		
		private function parseNextNode():void
		{
			var startTime:Date = new Date();
			var idx:int = 0;
			
			while(myIndex < nodes.length())
			{
				try
				{
					var nodeXml:XML = nodes[myIndex];
					
					var node:PhysicalNode = new PhysicalNode(manager);
					
					// Get location info
					var lat:Number = PhysicalLocation.defaultLatitude;
					var lng:Number = PhysicalLocation.defaultLongitude;
					var country:String = "Unknown";
					if(nodeXml.defaultNamespace::location.length() == 1)
					{
						var locationXml:XML = nodeXml.defaultNamespace::location[0];
						if(Number(locationXml.@latitude)
							&& Number(locationXml.@latitude) != 0
							&& Number(locationXml.@longitude)
							&& Number(locationXml.@longitude) != 0)
						{
							lat = Number(locationXml.@latitude);
							lng = Number(locationXml.@longitude);
						}
						country = String(locationXml.@country);
					}
					
					// Assign to a group based on location
					var location:PhysicalLocation = manager.locations.getAt(lat,lng);
					if(location == null)
					{
						location = new PhysicalLocation(manager, lat, lng, country);
						manager.locations.add(location);
					}
					node.location = location;
					location.nodes.add(node); 
					node.name = String(nodeXml.@component_name);
					switch(manager.advertisement.info.version)
					{
						case 0.1:
						case 0.2:
							node.id = new IdnUrn(String(nodeXml.@component_uuid));
							if(nodeXml.defaultNamespace::exclusive.length() == 1)
							{
								var exclusiveXml:XML = nodeXml.defaultNamespace::exclusive[0];
								node.exclusive = exclusiveXml.toString() == "true";
							}
							break;
						case 2:
						case 3:
						default:
							node.id = new IdnUrn(String(nodeXml.@component_id));
							node.exclusive = String(nodeXml.@exclusive) == "true";
					}
					
					// Add sliver types
					if(manager.advertisement.info.version < 2)
					{
						for each(var nodeTypeXml:XML in nodeXml.defaultNamespace::node_type)
						{
							var newNodeType:HardwareType = new HardwareType(
								String(nodeTypeXml.@type_name),
								Number(nodeTypeXml.@type_slots)
							);
							node.hardwareTypes.add(newNodeType);
							var nodeTypeSliverType:SliverType = null;
							switch(newNodeType.name)
							{
								case "pcvm":
									if(node.manager.type != FlackManager.TYPE_PLANETLAB)
									{
										
node.sliverTypes.add(new SliverType(EmulabXenSliverType.TYPE_EMULABXEN));
node.sliverTypes.add(new SliverType(EmulabOpenVzSliverType.TYPE_EMULABOPENVZ));
										nodeTypeSliverType = node.sliverTypes.collection[node.sliverTypes.length-1];
									}
									break;
								case "pc":
									if(node.exclusive && node.manager.type != FlackManager.TYPE_PLANETLAB)
									{
										node.sliverTypes.add(new SliverType(RawPcSliverType.TYPE_RAWPC_V2));
										nodeTypeSliverType = node.sliverTypes.collection[node.sliverTypes.length-1];
									}
									break;
								case JuniperRouterSliverType.TYPE_JUNIPER_LROUTER:
									node.sliverTypes.add(new SliverType(JuniperRouterSliverType.TYPE_JUNIPER_LROUTER));
									nodeTypeSliverType = node.sliverTypes.collection[node.sliverTypes.length-1];
									break;
								case "bbgeni":
									node.sliverTypes.add(new SliverType(EmulabBbgSliverType.TYPE_EMULAB_BBG));
									nodeTypeSliverType = node.sliverTypes.collection[node.sliverTypes.length-1];
									break;
								case "spp":
									node.sliverTypes.add(new SliverType(EmulabSppSliverType.TYPE_EMULAB_SPP));
									nodeTypeSliverType = node.sliverTypes.collection[node.sliverTypes.length-1];
									break;
								case "netfpga2":
									node.sliverTypes.add(new SliverType(Netfpga2SliverType.TYPE_NETFPGA2));
									nodeTypeSliverType = node.sliverTypes.collection[node.sliverTypes.length-1];
									break;
								default:
							}
							if(nodeTypeSliverType != null)
								manager.supportedSliverTypes.getOrCreateByName(nodeTypeSliverType.name);
						}
					}
					else
					{
						for each(var nodeSliverTypeXml:XML in nodeXml.defaultNamespace::sliver_type)
						{
							var newSliverType:SliverType = new SliverType(String(nodeSliverTypeXml.@name));
							var supportedSliverType:SupportedSliverType = (node.manager as GeniManager).supportedSliverTypes.getByName(newSliverType.name);
							// Don't add non-VMs if node is shared
							if(!node.exclusive && supportedSliverType != null && !supportedSliverType.supportsShared)
								continue;
							var managerSliverType:SliverType = manager.supportedSliverTypes.getOrCreateByName(newSliverType.name).type;
							for each(var sliverTypeChildXml:XML in nodeSliverTypeXml.children())
							{
								if(sliverTypeChildXml.namespace() == defaultNamespace)
								{
									if(sliverTypeChildXml.localName() == "disk_image")
									{
										var newSliverDiskImage:DiskImage = managerSliverType.diskImages.getByLongId(String(sliverTypeChildXml.@name));
										if(newSliverDiskImage == null)
										{
											newSliverDiskImage = new DiskImage(
												String(sliverTypeChildXml.@name),
												String(sliverTypeChildXml.@os),
												String(sliverTypeChildXml.@version),
												String(sliverTypeChildXml.@description),
												String(sliverTypeChildXml.@default) == "true",
												String(sliverTypeChildXml.@url));
											managerSliverType.diskImages.add(newSliverDiskImage);
										}
										if(newSliverType.diskImages.getByLongId(newSliverDiskImage.id.full) == null)
											newSliverType.diskImages.add(newSliverDiskImage);
									}
								}
							}
							if(newSliverType.sliverTypeSpecific != null)
								newSliverType.sliverTypeSpecific.applyFromAdvertisedSliverTypeXml(node, nodeSliverTypeXml);
							node.sliverTypes.add(newSliverType);
						}
						
						// Add hardware types and implicit sliver_types
						for each(var hardwareTypeXml:XML in nodeXml.defaultNamespace::hardware_type)
						{
							var newHardwareType:HardwareType = new HardwareType(String(hardwareTypeXml.@name));
							var emulabNodeTypes:XMLList = hardwareTypeXml.child(new QName(RspecUtil.emulabNamespace, "node_type"));
							if(emulabNodeTypes.length() == 1)
							{
								if(emulabNodeTypes[0].@type_slots == "unlimited")
									newHardwareType.slots = Number.MAX_VALUE;
								else
									newHardwareType.slots = Number(emulabNodeTypes[0].@type_slots);
							}
							node.hardwareTypes.add(newHardwareType);
							var hardwareTypeSliverType:SliverType = node.sliverTypes.getByName(newHardwareType.name);
							if(hardwareTypeSliverType == null)
							{
								switch(newHardwareType.name)
								{
									case JuniperRouterSliverType.TYPE_JUNIPER_LROUTER:
										hardwareTypeSliverType = new SliverType(JuniperRouterSliverType.TYPE_JUNIPER_LROUTER);
										break;
									case "bbgeni":
										hardwareTypeSliverType = new SliverType(EmulabBbgSliverType.TYPE_EMULAB_BBG);
										break;
									case "spp":
										hardwareTypeSliverType = new SliverType(EmulabSppSliverType.TYPE_EMULAB_SPP);
										break;
									case "netfpga2":
										hardwareTypeSliverType = new SliverType(Netfpga2SliverType.TYPE_NETFPGA2);
										break;
									default:
								}
								if(hardwareTypeSliverType != null)
								{
									node.sliverTypes.add(hardwareTypeSliverType);
									manager.supportedSliverTypes.getOrCreateByName(hardwareTypeSliverType.name);
								}
							}
						}
					}
					
					for each(var nodeChildXml:XML in nodeXml.children())
					{
						if(nodeChildXml.namespace() == defaultNamespace)
						{
							if(nodeChildXml.localName() == "interface")
							{
								var i:PhysicalInterface = new PhysicalInterface(node);
								i.id = new IdnUrn(String(nodeChildXml.@component_id));
								i.role = PhysicalInterface.RoleIntFromString(String(nodeChildXml.@role));
								i.publicIPv4 = String(nodeChildXml.@public_ipv4);
								node.interfaces.add(i);
								interfaceDictionary[i.id.full] = i;
							}
							else if(nodeChildXml.localName() == "available")
							{
								switch(manager.advertisement.info.version)
								{
									case 0.1:
									case 0.2:
										node.available = nodeChildXml.toString().toLowerCase() == "true";
										break;
									case 2:
									default:
										node.available = String(nodeChildXml.@now).toLowerCase() == "true";
								}
							}
							else if(nodeChildXml.localName() == "relation")
							{
								var relationType:String = String(nodeChildXml.@type);
								if(relationType == "subnode_of")
								{
									var parentId:String = String(nodeChildXml.@component_id);
									if(parentId.length > 0)
										subnodeList.push({subNode:node, parentName:parentId});
								}
							}
							else if(nodeChildXml.localName() == "disk_image")
							{
								var addToSliverType:SliverType = node.sliverTypes.getByName(RawPcSliverType.TYPE_RAWPC_V2);
								if(addToSliverType == null)
								{
									if(node.sliverTypes.getByName("N/A") == null)
										node.sliverTypes.add(new SliverType("N/A"));
									addToSliverType = node.sliverTypes.collection[0];
								}
								
								var managerAddToSliverType:SliverType = manager.supportedSliverTypes.getOrCreateByName(addToSliverType.name).type;
								var newDiskImage:DiskImage = managerAddToSliverType.diskImages.getByLongId(String(nodeChildXml.@name));
								if(newDiskImage == null)
								{
									newDiskImage = new DiskImage(
										String(nodeChildXml.@name),
										String(nodeChildXml.@os),
										String(nodeChildXml.@version),
										String(nodeChildXml.@description),
										String(nodeChildXml.@default) == "true",
										String(nodeChildXml.@url));
									managerAddToSliverType.diskImages.add(newDiskImage);
								}
								if(addToSliverType.diskImages.getByLongId(newDiskImage.id.full) == null)
									addToSliverType.diskImages.add(newDiskImage);
							}
							// Depreciated
							else if(nodeChildXml.localName() == "subnode_of")
							{
								var parentName:String = nodeChildXml.toString();
								if(parentName.length > 0)
									subnodeList.push({subNode:node, parentName:parentName});
							}
						}
						else if(nodeChildXml.namespace() == RspecUtil.emulabNamespace)
						{
							if(nodeChildXml.localName() == "fd")
							{
								if(nodeChildXml.@name == "cpu")
								{
									node.cpuSpeed = int(nodeChildXml.@weight);
								}
								else if(nodeChildXml.@name == "ram")
								{
									node.ramSize = int(nodeChildXml.@weight);
								}
							}
						}
					}
					
					// This shouldn't be, but if it is try to fix
					if(node.sliverTypes.length == 0)
					{
						if(node.hardwareTypes.getByName("pcpg") != null)
							node.sliverTypes.add(new SliverType(RawPcSliverType.TYPE_RAWPC_V2));
						if(node.hardwareTypes.getByName("pcvmpg") != null)
							node.sliverTypes.add(new SliverType(EmulabOpenVzSliverType.TYPE_EMULABOPENVZ));
					}
					
					node.advertisement = nodeXml.toXMLString();
					nodeNameDictionary[node.id] = node;
					nodeNameDictionary[node.name] = node;
					manager.nodes.add(node);
				}
				// skip if some problem
				catch(e:Error)
				{
					skippedNodes++;
				}
				idx++;
				myIndex++;
				if(((new Date()).time - startTime.time) > 60)
					return;
			}
			
			// Assign subnodes
			for each(var obj:Object in subnodeList)
			{
				var parentNode:PhysicalNode = nodeNameDictionary[obj.parentName];
				if(parentNode != null)
				{
					var subNode:PhysicalNode = obj.subNode;
					parentNode.subNodes = new Vector.<PhysicalNode>();
					// Hack so user doesn't try to get subnodes of nodes which aren't available
					if(!parentNode.available)
						subNode.available = false;
					parentNode.subNodes.push(subNode);
					obj.subNode.subNodeOf = parentNode;
				}
			}
			
			myState = LINK_PARSE;
			myIndex = 0;
			return;
		}
		
		private function parseNextLink():void
		{
			var startTime:Date = new Date();
			var idx:int = 0;
			
			while(myIndex < links.length())
			{
				try
				{
					var linkXml:XML = links[myIndex];
					var l:PhysicalLink = new PhysicalLink(manager);
					
					// Get interfaces and locations used
					var referencedInterface:PhysicalInterface;
					for each(var interfaceRefXml:XML in linkXml.defaultNamespace::interface_ref)
					{
						var interfaceId:String;
						if(manager.advertisement.info.version < 1)
							interfaceId = String(interfaceRefXml.@component_interface_id);
						else
							interfaceId = String(interfaceRefXml.@component_id);
						
						referencedInterface = interfaceDictionary[interfaceId];
						if(referencedInterface != null)
							l.interfaces.add(referencedInterface);
						else
						{
							addMessage(
								"Interface not found", "Interface '"+interfaceId+"' was not found",
								LogMessage.LEVEL_WARNING
							);
							// Stop parsing the link
							throw new Error();
						}
					}
					
					// Add outside references
					for each(referencedInterface in l.interfaces.collection)
					{
						referencedInterface.links.add(l);
						if(!referencedInterface.owner.location.links.contains(l))
							referencedInterface.owner.location.links.add(l);
					}
					
					l.advertisement = linkXml.toXMLString();
					l.name = String(linkXml.@component_name);
					if(manager.advertisement.info.version < 1)
						l.id = new IdnUrn(String(linkXml.@component_uuid));
					else
						l.id = new IdnUrn(String(linkXml.@component_id));
					
					for each(var ix:XML in linkXml.children())
					{
						if(ix.namespace() == defaultNamespace)
						{
							if(ix.localName() == "property")
							{
								var sourceInterface:PhysicalInterface = manager.nodes.getInterfaceById(ix.@source_id);
								var destInterface:PhysicalInterface = manager.nodes.getInterfaceById(ix.@dest_id);
								var newProperty:Property = new Property(sourceInterface, destInterface);
								if(ix.@capacity.length() == 1)
									newProperty.capacity = Number(ix.@capacity);
								if(ix.@latency.length() == 1)
									newProperty.latency = Number(ix.@latency);
								if(ix.@packet_loss.length() == 1)
									newProperty.packetLoss = Number(ix.@packet_loss);
								l.properties.add(newProperty);
							}
							else if(ix.localName() == "link_type")
							{
								var s:String;
								if(manager.advertisement.info.version < 1)
									s = String(ix.@type_name);
								else
									s = String(ix.@name);
								l.linkTypes.push(s);
							}
							// Depreciated
							else if(ix.localName() == "bandwidth")
								l.Capacity = Number(ix);
							else if(ix.localName() == "latency")
								l.Latency = Number(ix);
							else if(ix.localName() == "packet_loss")
								l.PacketLoss = Number(ix);
						}
					}
					
					manager.links.add(l);
				}
				// skip if some problem
				catch(e:Error)
				{
					skippedLinks++;
					var stackTrace:String = e.getStackTrace();
					trace(stackTrace);
				}
				idx++;
				myIndex++;
				if(((new Date()).time - startTime.time) > 60)
				{
					return;
				}
			}
			
			myState = DONE;
			return;
		}
		
		override protected function afterError(taskError:TaskError):void
		{
			manager.Status = FlackManager.STATUS_FAILED;
			
			super.afterError(taskError);
		}
		
		override protected function runCancel():void {
			manager.Status = FlackManager.STATUS_FAILED;
		}
		
		override protected function runCleanup():void
		{
			nodes = null;
			links = null;
			System.disposeXML(xmlDocument);
		}
	}
}
