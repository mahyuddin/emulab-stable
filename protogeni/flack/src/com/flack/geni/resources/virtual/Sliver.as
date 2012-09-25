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

package com.flack.geni.resources.virtual
{
	import com.flack.geni.resources.Extensions;
	import com.flack.geni.resources.docs.GeniCredential;
	import com.flack.geni.resources.sites.GeniManager;
	import com.flack.shared.resources.IdentifiableObject;
	import com.flack.shared.resources.docs.Rspec;
	import com.flack.shared.resources.docs.RspecVersion;
	
	import flash.utils.Dictionary;

	/**
	 * Holds resources for a slice at one manager
	 * 
	 * @author mstrum
	 * 
	 */
	public class Sliver extends IdentifiableObject
	{
		public static const STATE_STARTED:String = "started";
		public static const STATE_STOPPED:String = "stopped";
		public static const STATE_MIXED:String = "mixed";
		public static const STATE_NA:String = "N/A";
		
		public static const STATUS_CHANGING:String = "changing";
		public static const STATUS_READY:String = "ready";
		public static const STATUS_NOTREADY:String = "notready";
		public static const STATUS_FAILED:String = "failed";
		public static const STATUS_UNKNOWN:String = "unknown";
		public static const STATUS_MIXED:String = "mixed";
		public static const STATUS_NA:String = "N/A";
		public static const STATUS_STOPPED:String = "stopped";
		
		public static const ALLOCATION_UNALLOCATED:String = "geni_unallocated";
		public static const ALLOCATION_ALLOCATED:String = "geni_allocated";
		public static const ALLOCATION_PROVISIONED:String = "geni_provisioned";
		
		[Bindable]
		public var slice:Slice;
		[Bindable]
		public var manager:GeniManager;
		
		public var credential:GeniCredential;
		public var expires:Date = null;
		
		[Bindable]
		public var forceUseInputRspecInfo:RspecVersion;
		
		/**
		 * 
		 * @return Manually selected version, slice-selected version, or the max supported version
		 * 
		 */
		public function get UseInputRspecInfo():RspecVersion
		{
			if(forceUseInputRspecInfo != null)
				return forceUseInputRspecInfo;
			else
			{
				if(manager.inputRspecVersions.get(slice.useInputRspecInfo.type, slice.useInputRspecInfo.version) != null)
					return slice.useInputRspecInfo;
				else
					return manager.inputRspecVersions.UsableRspecVersions.MaxVersion;
			}
		}
		
		public var state:String = "";
		public var status:String = "";
		public var allocationStatus:String = "";
		public var operationalStatus:String = "";
		public var error:String = "";
		public function get StatusFinalized():Boolean
		{
			return status == STATUS_READY
				|| status == STATUS_FAILED
				|| status == STATUS_UNKNOWN
				|| status == STATUS_STOPPED;
		}
		public function clearStatus():void
		{
			state = "";
			status = "";
			var clearNodes:VirtualNodeCollection = slice.nodes.getByManager(manager);
			for each(var node:VirtualNode in clearNodes.collection)
				node.clearState();
			var clearLinks:VirtualLinkCollection = slice.links.getConnectedToManager(manager);
			for each(var link:VirtualLink in clearLinks.collection)
				link.clearState();
		}
		
		public var sliverIdToStatus:Dictionary = new Dictionary();
		
		public var ticket:String = "";
		public var manifest:Rspec = null;
		
		private var unsubmittedChanges:Boolean = true;
		public function get UnsubmittedChanges():Boolean
		{
			if(unsubmittedChanges)
				return true;
			if(slice.nodes.getByManager(manager).UnsubmittedChanges)
				return true;
			if(slice.links.getConnectedToManager(manager).UnsubmittedChanges)
				return true;
			return false;
		}
		public function set UnsubmittedChanges(value:Boolean):void
		{
			unsubmittedChanges = value;
		}
		
		public var extensions:Extensions = new Extensions();
		
		public function get Created():Boolean
		{
			return manifest != null;
		}
		
		public function get Nodes():VirtualNodeCollection
		{
			return slice.nodes.getByManager(manager);
		}
		
		public function get Links():VirtualLinkCollection
		{
			return slice.links.getConnectedToManager(manager);
		}
		
		/**
		 * 
		 * @param owner Slice for the sliver
		 * @param newManager Manager where the sliver lies
		 * 
		 */
		public function Sliver(owner:Slice,
							   newManager:GeniManager = null)
		{
			super();
			slice = owner;
			manager = newManager;
		}
		
		/**
		 * Removes status and manifests from everything from this sliver, BUT not the sliver's manifest
		 * 
		 */
		public function markStaged():void
		{
			// XXX unsubmittedChanges?
			
			state = "";
			status = "";
			if(slice != null)
			{
				for each(var virtualNode:VirtualNode in slice.nodes.collection)
				{
					if(virtualNode.manager == manager)
						virtualNode.markStaged();
				}
				for each(var virtualLink:VirtualLink in slice.links.collection)
				{
					for each(var linkManager:GeniManager in virtualLink.interfaceRefs.Interfaces.Managers.collection)
					{
						if(linkManager == manager)
						{
							virtualLink.markStaged();
							break;
						}
					}
					
				}
			}
		}
		
		public function removeFromSlice():void
		{
			var i:int = 0;
			// Remove the nodes
			for(i = 0; i < slice.nodes.length; i++)
			{
				var node:VirtualNode = slice.nodes.collection[i];
				if(node.manager == manager)
				{
					node.removeFromSlice();
					i--;
				}
			}
			// Remove the links (should only be any w/o interfaces to nodes)
			for(i = 0; i < slice.links.length; i++)
			{
				var link:VirtualLink = slice.links.collection[i];
				if(link.managerRefs.contains(manager))
				{
					link.managerRefs.remove(manager);
					if(link.managerRefs.length == 0 && link.interfaceRefs.length == 0)
					{
						link.removeFromSlice();
					}
					i--;
				}
			}
			// unsubmittedChanges = true;
			slice.reportedManagers.remove(manager);
			slice.slivers.remove(this);
		}
		
		override public function toString():String
		{
			return "[Sliver ID="+id.full+", Manager="+manager.id.full+", HasManifest="+Created+", Status="+status+", State="+state+"]";
		}
	}
}