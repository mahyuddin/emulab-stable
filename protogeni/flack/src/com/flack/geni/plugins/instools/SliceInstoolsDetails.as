/* GENIPUBLIC-COPYRIGHT
* Copyright (c) 2008-2012 University of Utah and the Flux Group,
* University of Kentucky and the Laboratory for Advanced Networking.
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

package com.flack.geni.plugins.instools
{
	import com.adobe.crypto.SHA1;
	import com.flack.geni.GeniMain;
	import com.flack.geni.resources.virtual.Slice;
	import com.flack.geni.resources.virtual.Sliver;
	
	import flash.net.URLRequest;
	import flash.net.URLVariables;
	import flash.net.navigateToURL;
	import flash.utils.Dictionary;

	public final class SliceInstoolsDetails
	{
		public var slice:Slice;
		public var apiVersion:Number;
		public var creating:Boolean;
		public var useVirtualMCs:Boolean;
		public var useStableINSTOOLS:Boolean;
		
		public var updated_rspec:Dictionary = new Dictionary();
		public var rspec_version:Dictionary = new Dictionary();
		public var cmurn_to_contact:Dictionary = new Dictionary();
		
		public var instools_status:Dictionary = new Dictionary();
		public var portal_url:Dictionary = new Dictionary();
		public var started_instrumentize:Dictionary = new Dictionary();
		public var started_MC:Dictionary = new Dictionary();
		public var MC_present:Dictionary = new Dictionary();
		
		public function SliceInstoolsDetails(useSlice:Slice, useApiVersion:Number, isCreating:Boolean = true, shouldUseVirtualMCs:Boolean = false, shouldUseStableINSTOOLS:Boolean = true)
		{
			slice = useSlice;
			apiVersion = useApiVersion;
			creating = isCreating;
			useVirtualMCs = shouldUseVirtualMCs;
			useStableINSTOOLS = shouldUseStableINSTOOLS;
		}
		
		public function clearAll():void
		{
			updated_rspec = new Dictionary();
			rspec_version = new Dictionary();
			cmurn_to_contact = new Dictionary();
			instools_status = new Dictionary();
			portal_url = new Dictionary();
			started_instrumentize = new Dictionary();
			started_MC = new Dictionary();
			MC_present = new Dictionary();
		}
		
		public function hasAnyPortal():Boolean
		{
			for each(var sliver:Sliver in slice.slivers.collection)
			{
				if(portal_url[sliver.manager.id.full] != null
					&& portal_url[sliver.manager.id.full].length > 0)
					return true;
			}
			return false;
		}
		
		/**
		 * Opens a browser to the instools portal site
		 * 
		 * @param slice
		 * 
		 */
		public function goToPortal():void
		{
			var out:String = SHA1.hash(GeniMain.geniUniverse.user.password);
			//var boo:String = "secretkey";
			//var out:String = Util.rc4encrypt(boo,data);
			//out = encodeURI(out);
			var userinfo:Array = GeniMain.geniUniverse.user.hrn.split(".");
			var portalURL:String = "https://portal.uky.emulab.net/geni/portal/log_on_slice.php";
			var portalVars:URLVariables = new URLVariables();
			portalVars.user = userinfo[1];
			portalVars.cert = userinfo[0];
			portalVars.slice = slice.Name;
			portalVars.pass = out;
			var req:URLRequest = new URLRequest(portalURL);
			req.data = portalVars;
			navigateToURL(req, "_blank");
		}
	}
}