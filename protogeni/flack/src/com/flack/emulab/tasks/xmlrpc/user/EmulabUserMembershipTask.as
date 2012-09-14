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

package com.flack.emulab.tasks.xmlrpc.user
{
	import com.flack.emulab.EmulabMain;
	import com.flack.emulab.tasks.xmlrpc.EmulabXmlrpcTask;
	
	import flash.utils.Dictionary;
	
	public class EmulabUserMembershipTask extends EmulabXmlrpcTask
	{
		private const PERMISSION_READINFO:String = "readinfo";
		private const PERMISSION_CREATEEXPT:String = "createexpt";
		private const PERMISSION_MAKEGROUP:String = "makegroup";
		private const PERMISSION_MAKEOSID:String = "makeosid";
		private const PERMISSION_MAKEIMAGEID:String = "makeimageid";
		
		// optional
		private var permission:String;
		public function EmulabUserMembershipTask(newPermission:String = "")
		{
			super(
				EmulabMain.manager.api.url,
				EmulabXmlrpcTask.MODULE_USER,
				EmulabXmlrpcTask.METHOD_MEMBERSHIP,
				"Get number of used nodes @ " + EmulabMain.manager.api.url,
				"Getting node availability at " + EmulabMain.manager.api.url,
				"# Nodes Used"
			);
			permission = newPermission;
			relatedTo.push(EmulabMain.user);
			relatedTo.push(EmulabMain.manager);
		}
		
		override protected function createFields():void
		{
			addOrderedField(version);
			var args:Dictionary = new Dictionary();
			if(permission.length > 0)
				args["permission"] = permission;
			addOrderedField(args);
		}
		
		override protected function afterComplete(addCompletedMessage:Boolean=false):void
		{
			if (code == EmulabXmlrpcTask.CODE_SUCCESS)
			{/*
				for(var projName:String in data)
				{
					var subGroup:String = data[projName];
					var subId:String = IdnUrn.makeFrom(projName+":"+subGroup, "subgroup", "subgroup").full;
					
					if(user.subAuthorities.getById(subId) == null)
					{
						var newAuthority:EmulabAuthority = new EmulabAuthority(subId, user.authority.url, false, user.authority as EmulabAuthority);
						user.subAuthorities.add(newAuthority);
					}
					
				}
				
				SharedMain.sharedDispatcher.dispatchUserChanged();
				*/
				super.afterComplete(addCompletedMessage);
			}
			else
				faultOnSuccess();
		}
	}
}