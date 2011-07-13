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
	import com.mattism.http.xmlrpc.MethodFault;
	
	import flash.events.ErrorEvent;
	
	import protogeni.GeniEvent;
	import protogeni.Util;
	import protogeni.resources.GeniManager;
	import protogeni.resources.IdnUrn;
	import protogeni.resources.Slice;
	import protogeni.resources.Sliver;
	
	/**
	 * Gets some info for the sliver like the sliver credential using the ProtoGENI API
	 * 
	 * @author mstrum
	 * 
	 */
	public final class RequestSliverGet extends Request
	{
		public var sliver:Sliver;
		
		public function RequestSliverGet(s:Sliver):void
		{
			super("Get credential @ " + s.manager.Hrn,
				"Getting the sliver credential on " + s.manager.Hrn + " on slice named " + s.slice.Name,
				CommunicationUtil.getSliver,
				true,
				true);
			sliver = s;
			sliver.changing = true;
			sliver.message = "Getting credential";
			Main.geniDispatcher.dispatchSliceChanged(sliver.slice, GeniEvent.ACTION_STATUS);
			
			// Build up the args
			op.addField("slice_urn", sliver.slice.urn.full);
			op.addField("credentials", [sliver.slice.credential]);
			op.setUrl(sliver.manager.Url);
		}
		
		override public function start():Operation {
			if(sliver.manager.Status == GeniManager.STATUS_VALID)
				return op;
			else
				return null;
		}
		
		override public function complete(code:Number, response:Object):*
		{
			var newCall:Request = null;
			if (code == CommunicationUtil.GENIRESPONSE_SUCCESS)
			{
				sliver.credential = String(response.value);
				
				var cred:XML = new XML(response.value);
				sliver.urn = new IdnUrn(cred.credential.target_urn);
				sliver.expires = Util.parseProtogeniDate(cred.credential.expires);
				
				sliver.message = "Credential recieved";
				newCall = new RequestSliverResolve(sliver);
			}
			else if(code == CommunicationUtil.GENIRESPONSE_SEARCHFAILED
				|| code == CommunicationUtil.GENIRESPONSE_BADARGS)
			{
				sliver.slice.slivers.remove(sliver);
				var old:Slice = Main.geniHandler.CurrentUser.slices.getByUrn(sliver.slice.urn.full);
				if(old != null)
				{
					var oldSliver:Sliver = old.slivers.getByManager(sliver.manager);
					if(oldSliver != null)
						old.slivers.remove(oldSliver);
				}
				sliver.changing = false;
				sliver.message = "No sliver here";
			}
			
			return newCall;
		}
		
		public function failed(msg:String = ""):void {
			sliver.changing = false;
			sliver.message = "Get credential failed";
			if(msg != null && msg.length > 0)
				sliver.message += ": " + msg;
		}
		
		override public function fail(event:ErrorEvent, fault:MethodFault):* {
			failed(fault.getFaultString());
			return super.fail(event, fault);
		}
		
		override public function cleanup():void {
			super.cleanup();
			Main.geniDispatcher.dispatchSliceChanged(sliver.slice);
		}
	}
}
