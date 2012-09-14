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

package com.flack.geni
{
	import com.flack.geni.resources.sites.GeniManager;
	import com.flack.geni.resources.sites.GeniManagerCollection;
	import com.flack.geni.resources.sites.managers.OpenflowAggregateManager;
	import com.flack.geni.resources.sites.managers.PlanetlabAggregateManager;
	import com.flack.geni.resources.sites.managers.ProtogeniComponentManager;
	import com.flack.shared.SharedCache;
	import com.flack.shared.SharedMain;
	import com.flack.shared.resources.sites.ApiDetails;
	import com.flack.shared.resources.sites.FlackManager;
	
	import flash.utils.Dictionary;

	/**
	 * Handles saving and loading data from a cache kept on the client computer.
	 * 
	 * OSes other than Windows can have issues...
	 * 
	 * @author mstrum
	 * 
	 */
	public final class GeniCache
	{
		private static var ignoreUpdate:Boolean = false;
		
		public function GeniCache()
		{
		}
		
		/*
		public static function initialize():void
		{
		SharedMain.geniDispatcher.addEventListener(FlackEvent.CHANGED_AUTHORITIES, updateAuthorties);
		SharedMain.geniDispatcher.addEventListener(FlackEvent.CHANGED_MANAGERS, updateManagers);
		}
		
		// Update with live data
		public static function updateAuthorties(event:FlackEvent):void
		{
			if(ignoreUpdate)
			{
				ignoreUpdate = false;
				return;
			}
			if(SharedCache._sharedObject == null || !SharedCache.UsableCache() || event.action != FlackEvent.ACTION_POPULATED)
				return;
			
			SharedCache._sharedObject.data.authoritiesCreated = new Date();
			SharedCache._sharedObject.data.authorities = [];
			for each(var authority:GeniAuthority in GeniMain.geniUniverse.authorities.collection)
			{
				SharedCache._sharedObject.data.authorities.push(
					{
						id:authority.id.full,
						url:authority.url,
						workingCertGet:authority.workingCertGet
					}
				);
			}
		}
		
		public static function updateManagers(event:FlackEvent):void
		{
			if(ignoreUpdate)
			{
				ignoreUpdate = false;
				return;
			}
			if(SharedCache._sharedObject == null || !SharedCache.UsableCache() || event.action != FlackEvent.ACTION_POPULATED)
				return;
			
			SharedCache._sharedObject.data.managersCreated = new Date();
			SharedCache._sharedObject.data.managers = [];
			for each(var manager:GeniManager in GeniMain.geniUniverse.managers.collection)
			{
				SharedCache._sharedObject.data.managers.push(
					{
						id:manager.id.full,
						url:manager.url,
						hrn:manager.hrn,
						type:manager.type,
						api:manager.api
					}
				);
			}
		}
		*/
		
		// Managers to list
		public static function shouldAskWhichManagersToWatch():Boolean
		{
			if(SharedCache._sharedObject == null || SharedCache._sharedObject.data.askWhichManagersToWatch == null)
				return true;
			
			// If list of managers is different than list stored, ask
			var managersToWatch:Dictionary = GeniCache.getManagersToWatch();
			for each(var manager:GeniManager in GeniMain.geniUniverse.managers.collection)
			{
				if(managersToWatch[manager.id.full] == null)
					return true;
			}
			
			return SharedCache._sharedObject.data.askWhichManagersToWatch;
		}
		
		public static function setAskWhichManagersToWatch(value:Boolean):void
		{
			if(SharedCache._sharedObject == null)
				return;
			
			SharedCache._sharedObject.data.askWhichManagersToWatch = value;
		}
		
		public static function setManagersToWatch(managersToWatch:Dictionary):void
		{
			if(SharedCache._sharedObject == null)
				return;
			
			SharedCache._sharedObject.data.managersToWatch = [];
			for(var managerId:String in managersToWatch)
				SharedCache._sharedObject.data.managersToWatch.push({id:managerId, watch:managersToWatch[managerId]});
		}
		
		public static function getManagersToWatch():Dictionary
		{
			var results:Dictionary = new Dictionary();
			
			if(SharedCache._sharedObject != null && SharedCache._sharedObject.data.managersToWatch != null)
			{
				for each(var managerWatchObject:Object in SharedCache._sharedObject.data.managersToWatch)
					results[managerWatchObject.id] = managerWatchObject.watch;
			}
			
			return results;
		}
		
		public static function clearManagersToWatch():void
		{
			if(SharedCache._sharedObject != null)
			{
				delete SharedCache._sharedObject.data.managersToWatch;
				delete SharedCache._sharedObject.data.askWhichManagersToWatch;
			}
		}
		
		public static function getForceAmApi():Boolean
		{
			var forceAmApi:Boolean = false;
			
			if(SharedCache._sharedObject != null && SharedCache._sharedObject.data.forceAmApi != null)
			{
				forceAmApi = SharedCache._sharedObject.data.forceAmApi;
			}
			
			return forceAmApi;
		}
		
		public static function setForceAmApi(value:Boolean):void
		{
			if(SharedCache._sharedObject != null)
			{
				SharedCache._sharedObject.data.forceAmApi = value;
			}
		}
		
		// Manual managers
		public static function wasManagerManuallyAdded(manager:GeniManager):Boolean
		{
			if(SharedCache._sharedObject == null || SharedCache._sharedObject.data.manualManagers == null)
				return false;
			for each(var managerObject:Object in SharedCache._sharedObject.data.manualManagers)
			{
				if(managerObject.id == manager.id.full)
					return true;
			}
			return false;
		}
		
		public static function removeManuallyAddedManager(manager:GeniManager):void
		{
			if(SharedCache._sharedObject == null || SharedCache._sharedObject.data.manualManagers == null)
				return;
			for(var i:int = 0; i < SharedCache._sharedObject.data.manualManagers.length; i++)
			{
				if(SharedCache._sharedObject.data.manualManagers[i].id == manager.id.full)
				{
					SharedCache._sharedObject.data.manualManagers.splice(i, 1);
					return;
				}
			}
			return;
		}
		
		public static function addManagerManually(manager:GeniManager, managerCert:String):void
		{
			if(SharedCache._sharedObject == null || !SharedCache.UsableCache())
				return;
			
			if(SharedCache._sharedObject.data.manualManagers == null)
				SharedCache._sharedObject.data.manualManagers = [];
			
			SharedCache._sharedObject.data.manualManagers.push(
				{
					id:manager.id.full,
					url:manager.url,
					hrn:manager.hrn,
					type:manager.type,
					apitype:manager.api.type,
					cert:managerCert
				}
			);
		}
		
		public static function getManualManagers():GeniManagerCollection
		{
			var results:GeniManagerCollection = new GeniManagerCollection();
			
			if(SharedCache._sharedObject != null && SharedCache._sharedObject.data.manualManagers != null)
			{
				var managerCerts:String = "";
				for each(var managerObject:Object in SharedCache._sharedObject.data.manualManagers)
				{
					var newManager:GeniManager;
					switch(managerObject.type)
					{
						case FlackManager.TYPE_PLANETLAB:
							newManager = new PlanetlabAggregateManager(managerObject.id);
							break;
						case FlackManager.TYPE_PROTOGENI:
							newManager = new ProtogeniComponentManager(managerObject.id);
							break;
						case FlackManager.TYPE_OPENFLOW:
							newManager = new OpenflowAggregateManager(managerObject.id);
							break;
						default:
							newManager = new GeniManager(FlackManager.TYPE_OTHER, ApiDetails.API_GENIAM, managerObject.id);
					}
					newManager.url = managerObject.url;
					newManager.api.url = newManager.url;
					newManager.hrn = managerObject.hrn;
					newManager.api.type = managerObject.apitype;
					var newCert:String = managerObject.cert;
					if(newCert.length > 0 && SharedMain.Bundle.indexOf(newCert) == -1)
						managerCerts += newCert;
					results.add(newManager);
				}
				if(managerCerts.length > 0)
					SharedMain.Bundle += managerCerts;
			}
			return results;
		}
		
		public static function clearManualManagers():void
		{
			if(SharedCache._sharedObject != null)
			{
				delete SharedCache._sharedObject.data.manualManagers;
			}
		}
	}
}