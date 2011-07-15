﻿/* GENIPUBLIC-COPYRIGHT
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

package protogeni.communication
{
	import protogeni.Util;
	import protogeni.resources.AggregateManager;
	import protogeni.resources.GeniManager;
	import protogeni.resources.PlanetlabAggregateManager;
	import protogeni.resources.ProtogeniComponentManager;
	import protogeni.resources.Slice;
	import protogeni.resources.Sliver;
	
	public final class RequestSliceCredential extends Request
	{
		private var slice:Slice;
		private var exploreAllManagers:Boolean;
		
		/**
		 * Gets the slice credential from the user's slice authority using the ProtoGENI API
		 * 
		 * @param s slice which we need the credential for
		 * 
		 */
		public function RequestSliceCredential(newSlice:Slice, shouldExploreAllManagers:Boolean = false):void
		{
			super("Get credential for " + newSlice.Name,
				"Getting the slice credential for " + newSlice.Name,
				CommunicationUtil.getCredential,
				true);
			slice = newSlice;
			slice.Changing = true;
			exploreAllManagers = shouldExploreAllManagers;
			
			// Build up the args
			op.setExactUrl(Main.geniHandler.CurrentUser.authority.Url);
		}
		
		override public function start():Operation {
			op.clearFields();
			
			op.addField("credential", Main.geniHandler.CurrentUser.Credential);
			op.addField("urn", slice.urn.full);
			op.addField("type", "Slice");
			
			return op;
		}
		
		override public function complete(code:Number, response:Object):*
		{
			var newCalls:RequestQueue = new RequestQueue();
			if (code == CommunicationUtil.GENIRESPONSE_SUCCESS)
			{
				slice.credential = String(response.value);
				
				var cred:XML = new XML(slice.credential);
				slice.expires = Util.parseProtogeniDate(cred.credential.expires);
				
				var manager:GeniManager;
				var newSliver:Sliver;
				if(!exploreAllManagers) {
					for each(var s:Sliver in slice.slivers.collection) {
						if(s.manager.isAm)
							newCalls.push(new RequestSliverListResourcesAm(s));
						else
							newCalls.push(new RequestSliverGet(s));
					}
					
					for each(manager in Main.geniHandler.GeniManagers) {
						if(manager.isAm) {
							newSliver = new Sliver(slice, manager);
							Main.geniHandler.requestHandler.pushRequest(new RequestSliverListResourcesAm(newSliver));
						}
					}
				} else {
					for each(manager in Main.geniHandler.GeniManagers) {
						if(manager.Status != GeniManager.STATUS_VALID)
							continue;
						newSliver = new Sliver(slice, manager);
						if(manager.isAm)
							Main.geniHandler.requestHandler.pushRequest(new RequestSliverListResourcesAm(newSliver));
						else
							newCalls.push(new RequestSliverGet(newSliver));
					}
				}
				
			}
			
			return newCalls.head;
		}
		
		override public function cleanup():void {
			super.cleanup();
			slice.Changing = false;
			Main.geniDispatcher.dispatchSliceChanged(slice);
		}
	}
}
