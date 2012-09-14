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

package com.flack.shared
{
	import flash.display.Sprite;
	import flash.events.NetStatusEvent;
	import flash.net.SharedObject;
	import flash.net.SharedObjectFlushStatus;
	import flash.system.Capabilities;
	import flash.system.Security;
	import flash.system.SecurityPanel;
	
	import mx.controls.Alert;
	import mx.core.FlexGlobals;
	import mx.events.CloseEvent;

	/**
	 * Handles saving and loading data from a cache kept on the client computer.
	 * 
	 * OSes other than Windows can have issues...
	 * 
	 * @author mstrum
	 * 
	 */
	public final class SharedCache
	{
		public static var _sharedObject:SharedObject = null;
		public static function get Available():Boolean
		{
			return _sharedObject != null
				&& _sharedObject.size > 0;
		}
		
		public function SharedCache()
		{
		}
		
		public static function UsableCache():Boolean
		{
			// Only Windows doesn't usually error on cache
			return Capabilities.os.charAt(0) == "W";
		}
		
		public static function loadAndApply():void
		{
			try {
				_sharedObject = SharedObject.getLocal("geniCacheSharedObject");
				if(_sharedObject.size > 0)
				{
					// Expire any data older than 24 hours
					var expirePriorTo:Date = new Date();
					expirePriorTo.time -= 1000*60*60*24;
					
					if(_sharedObject.data.userPassword != null)
						SharedMain.user.password = _sharedObject.data.userPassword;
					if(_sharedObject.data.userSslCert != null)
						SharedMain.user.sslCert = _sharedObject.data.userSslCert;
					
					/*
					if(_sharedObject.data.certBundle != null)
					{
						if(_sharedObject.data.certBundleCreated.time > expirePriorTo.time)
							GeniMain.Bundle = _sharedObject.data.certBundle;
						else
							GeniMain.Bundle = "";
					}
					
					if(_sharedObject.data.authorities != null)
					{
						if(_sharedObject.data.authoritiesCreated.time > expirePriorTo.time)
						{
							GeniMain.geniUniverse.authorities = new GeniAuthorityCollection();
							for each(var authorityObj:Object in _sharedObject.data.authorities)
							{
								GeniMain.geniUniverse.authorities.add(
									new ProtogeniSliceAuthority(
										authorityObj.id,
										authorityObj.url,
										authorityObj.workingCertGet
									)
								);
							}
							ignoreUpdate = true;
							SharedMain.geniDispatcher.dispatchAuthoritiesChanged(GeniEvent.ACTION_POPULATED);
						}
						else
							_sharedObject.data.authorities = [];
					}
					
					if(_sharedObject.data.managers != null)
					{
						if(_sharedObject.data.managersCreated.time > expirePriorTo.time)
						{
							GeniMain.geniUniverse.managers = new GeniManagerCollection();
							for each(var managerObj:Object in _sharedObject.data.managers)
							{
								var newManager:GeniManager;
								if(managerObj.type == GeniManager.TYPE_PROTOGENI)
									newManager = new ProtogeniComponentManager();
								else if(managerObj.type == GeniManager.TYPE_PLANETLAB)
									newManager = new PlanetlabAggregateManager();
								else
									newManager = new GeniManager();
								newManager.api = managerObj.api;
								newManager.id = new IdnUrn(managerObj.id);
								newManager.url = managerObj.url;
								newManager.hrn = managerObj.hrn;
								
								GeniMain.geniUniverse.managers.add(newManager);
							}
							ignoreUpdate = true;
							SharedMain.geniDispatcher.dispatchManagersChanged(GeniEvent.ACTION_POPULATED);
						}
						else
							_sharedObject.data.managers = [];
					}
					*/
				}
			}
			catch(e:Error)
			{
				Alert.show(
					"Unable to create local cache. Open the storage settings where you can allow this application to use a local cache?",
					"Open storage settings?",
					Alert.YES|Alert.NO,
					FlexGlobals.topLevelApplication as Sprite,
					function allowData(e:CloseEvent):void
					{
						if(e.detail == Alert.YES)
							Security.showSettings(SecurityPanel.LOCAL_STORAGE);
					}
				);
				
			}
		}
		
		// User
		public static function updateUserSslPem(value:String):void
		{
			if(_sharedObject == null)
				return;
			
			_sharedObject.data.userSslCert = value;
		}
		
		public static function updateUserPassword(value:String):void
		{
			if(_sharedObject == null)
				return;
			
			_sharedObject.data.userPassword = value;
		}
		
		public static function clearUser():void
		{
			if(_sharedObject != null)
			{
				delete _sharedObject.data.userSslCert;
				delete _sharedObject.data.userPassword;
			}
		}
		
		// Cert bundle
		public static function updateCertBundle(value:String):void
		{
			if(_sharedObject == null || !UsableCache())
				return;
			
			_sharedObject.data.certBundleCreated = new Date();
			_sharedObject.data.certBundle = value;
		}
		
		public static function clearCertBundle():void
		{
			if(_sharedObject != null)
			{
				delete _sharedObject.data.certBundleCreated;
				delete _sharedObject.data.certBundle;
			}
		}
		
		/**
		 * Saves the basic cache to file
		 * 
		 */		
		public static function save():void
		{
			if(_sharedObject == null)
				return;
			
			var flushStatus:String = null;
			try
			{
				flushStatus = _sharedObject.flush();
			}
			catch (e:Error)
			{
				trace("Problem saving shared object");
			}
			
			// deal with dialog to increase cache size
			if (flushStatus != null)
			{
				switch (flushStatus)
				{
					case SharedObjectFlushStatus.PENDING:
						_sharedObject.addEventListener(NetStatusEvent.NET_STATUS, onFlushStatus);
						break;
					case SharedObjectFlushStatus.FLUSHED:
						// saved
						break;
				}
			}
		}
		
		/**
		 * Called after user closes dialog
		 * 
		 * @param event
		 * 
		 */		
		private static function onFlushStatus(event:NetStatusEvent):void
		{
			if(event.info.code == "SharedObject.Flush.Success")
			{
				// saved
			}
			else
			{
				// XXX chose not to allow storage. Don't try again...
			}
			
			_sharedObject.removeEventListener(NetStatusEvent.NET_STATUS, onFlushStatus);
		}
		
		/**
		 * Clears and removes the cache from file 
		 * 
		 */
		public static function clear():void
		{
			if(_sharedObject != null)
				_sharedObject.clear();
		}
	}
}