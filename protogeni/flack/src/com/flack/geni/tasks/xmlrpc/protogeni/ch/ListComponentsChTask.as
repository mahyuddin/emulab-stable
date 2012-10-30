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

package com.flack.geni.tasks.xmlrpc.protogeni.ch
{
	import com.flack.geni.GeniCache;
	import com.flack.geni.GeniMain;
	import com.flack.geni.plugins.emulab.DelaySliverType;
	import com.flack.geni.plugins.emulab.EmulabBbgSliverType;
	import com.flack.geni.plugins.emulab.EmulabSppSliverType;
	import com.flack.geni.plugins.emulab.FirewallSliverType;
	import com.flack.geni.plugins.planetlab.PlanetlabSliverType;
	import com.flack.geni.resources.GeniUser;
	import com.flack.geni.resources.SliverTypes;
	import com.flack.geni.resources.sites.GeniManager;
	import com.flack.geni.resources.sites.GeniManagerCollection;
	import com.flack.geni.resources.sites.SupportedSliverType;
	import com.flack.geni.resources.sites.managers.PlanetlabAggregateManager;
	import com.flack.geni.resources.sites.managers.ProtogeniComponentManager;
	import com.flack.geni.resources.virtual.LinkType;
	import com.flack.geni.tasks.xmlrpc.protogeni.ProtogeniXmlrpcTask;
	import com.flack.shared.FlackEvent;
	import com.flack.shared.SharedMain;
	import com.flack.shared.logging.LogMessage;
	import com.flack.shared.resources.IdnUrn;
	import com.flack.shared.resources.sites.ApiDetails;
	import com.flack.shared.resources.sites.FlackManager;
	import com.flack.shared.tasks.TaskError;
	import com.flack.shared.utils.StringUtil;
	
	/**
	 * Gets the list and information for the component managers listed at a clearinghouse
	 * 
	 * @author mstrum
	 * 
	 */
	public class ListComponentsChTask extends ProtogeniXmlrpcTask
	{
		public var user:GeniUser;
		
		/**
		 * 
		 * @param newUser User making the call, needed for this call
		 * 
		 */
		public function ListComponentsChTask(newUser:GeniUser)
		{
			super(
				GeniMain.geniUniverse.clearinghouse.url,
				ProtogeniXmlrpcTask.MODULE_CH,
				ProtogeniXmlrpcTask.METHOD_LISTCOMPONENTS,
				"List managers",
				"Gets the list and information for the component managers listed at a clearinghouse"
			);
			user = newUser;
		}
		
		override protected function createFields():void
		{
			addNamedField("credential", user.credential.Raw);
		}
		
		override protected function afterComplete(addCompletedMessage:Boolean=false):void
		{
			if (code == ProtogeniXmlrpcTask.CODE_SUCCESS)
			{
				GeniMain.geniUniverse.managers = new GeniManagerCollection();
				SharedMain.sharedDispatcher.dispatchChanged(
					FlackEvent.CHANGED_MANAGERS,
					null,
					FlackEvent.ACTION_REMOVED
				);
				
				for each(var obj:Object in data)
				{
					try
					{
						var newManager:GeniManager = null;
						var url:String = obj.url;
						url = url.replace(":12369", "");
						var newId:IdnUrn = new IdnUrn(obj.urn);
						
						// ProtoGENI Component Manager
						if(url.toLowerCase().lastIndexOf("/cm") == url.length - 3)
						{
							var protogeniManager:ProtogeniComponentManager = new ProtogeniComponentManager(newId.full);
							protogeniManager.hrn = obj.hrn;
							protogeniManager.url = url.substr(0, url.length-3);
							
							protogeniManager.supportedLinkTypes.getOrCreateByName(LinkType.GRETUNNEL_V2);
							protogeniManager.supportedLinkTypes.getOrCreateByName(LinkType.LAN_V2);
							protogeniManager.supportedLinkTypes.getOrCreateByName(LinkType.UNSPECIFIED);
							
							if(protogeniManager.hrn == "shadowgeni.cm")
							{
								protogeniManager.supportedLinkTypes.getByName(LinkType.LAN_V2).requiresIpAddresses = true;
							}
							
							// Link Types (not advertised...)
							if(protogeniManager.hrn == "ukgeni.cm"
								|| protogeniManager.hrn == "utahemulab.cm")
							{
								protogeniManager.supportedLinkTypes.getOrCreateByName(LinkType.ION);
							}
							if(protogeniManager.hrn == "wail.cm"
								|| protogeniManager.hrn == "utahemulab.cm")
							{
								protogeniManager.supportedLinkTypes.getOrCreateByName(LinkType.GPENI);
							}
							if(protogeniManager.hrn == "ukgeni.cm"
								|| protogeniManager.hrn == "utahemulab.cm"
								|| protogeniManager.hrn == "wail.cm"
								|| protogeniManager.hrn == "shadowgeni.cm")
							{
								protogeniManager.supportedLinkTypes.getOrCreateByName(LinkType.VLAN);
							}
							
							// Node Types (not advertised yet...)
							if(protogeniManager.hrn == "utahemulab.cm")
							{
								protogeniManager.supportedSliverTypes.getOrCreateByName(FirewallSliverType.TYPE_FIREWALL);
								protogeniManager.supportedSliverTypes.getOrCreateByName(EmulabSppSliverType.TYPE_EMULAB_SPP);
							}
							if(protogeniManager.hrn == "utahemulab.cm"
								|| protogeniManager.hrn == "ukgeni.cm"
								|| protogeniManager.hrn == "jonlab.cm")
							{
								protogeniManager.supportedSliverTypes.getOrCreateByName(DelaySliverType.TYPE_DELAY);
							}
							
							if(protogeniManager.hrn == "utahemulab.cm"
								|| protogeniManager.hrn == "ukgeni.cm"
								|| protogeniManager.hrn == "wail.cm")
							{
								protogeniManager.supportedSliverTypes.getOrCreateByName(EmulabBbgSliverType.TYPE_EMULAB_BBG);
							}
							
							
							newManager = protogeniManager;
						}
						else if(newId.name == ProtogeniXmlrpcTask.MODULE_SA)
						{
							var planetLabManager:PlanetlabAggregateManager = new PlanetlabAggregateManager(newId.full);
							planetLabManager.hrn = obj.hrn;
							//url = "https://sfa-devel.planet-lab.org:12346";//"https://sfa-devel.planet-lab.org:12346";
							planetLabManager.url = StringUtil.makeSureEndsWith(url, "/"); // needs this for forge...
							planetLabManager.registryUrl = planetLabManager.url.replace("12346", "12345");
							
							if(planetLabManager.hrn != "genicloud.hplabs.sa")
							{
								planetLabManager.supportedLinkTypes.getOrCreateByName(LinkType.GRETUNNEL_V2);
								planetLabManager.supportedLinkTypes.getOrCreateByName(LinkType.UNSPECIFIED);
							}
							
							planetLabManager.supportedSliverTypes.getOrCreateByName(PlanetlabSliverType.TYPE_PLANETLAB_V2);
							
							newManager = planetLabManager;
						}
						else
						{
							var otherManager:GeniManager = new GeniManager(FlackManager.TYPE_OTHER, ApiDetails.API_GENIAM, newId.full);
							otherManager.hrn = obj.hrn;
							otherManager.url = StringUtil.makeSureEndsWith(url, "/");
							
							otherManager.supportedLinkTypes.getOrCreateByName(LinkType.UNSPECIFIED);
							
							newManager = otherManager;
						}
						newManager.id = newId;
						newManager.api.url = newManager.url;
						
						GeniMain.geniUniverse.managers.add(newManager);
						
						addMessage(
							"Added manager",
							newManager.toString(),
							LogMessage.LEVEL_INFO,
							LogMessage.IMPORTANCE_HIGH
						);
						
						SharedMain.sharedDispatcher.dispatchChanged(
							FlackEvent.CHANGED_MANAGER,
							newManager,
							FlackEvent.ACTION_CREATED
						);
						
					}
					catch(e:Error)
					{
						addMessage(
							"Error adding",
							"Couldn't add manager from list:\n" + obj.toString(),
							LogMessage.LEVEL_WARNING,
							LogMessage.IMPORTANCE_HIGH
						);
					}
				}
				
				addMessage(
					"Added " + GeniMain.geniUniverse.managers.length + " manager(s)",
					"Added " + GeniMain.geniUniverse.managers.length + " manager(s)",
					LogMessage.LEVEL_INFO,
					LogMessage.IMPORTANCE_HIGH
				);
				
				var manuallyAddedManagers:GeniManagerCollection = GeniCache.getManualManagers();
				for each(var cachedManager:GeniManager in manuallyAddedManagers.collection)
				{
					if(GeniMain.geniUniverse.managers.getById(cachedManager.id.full) == null)
					{
						GeniMain.geniUniverse.managers.add(cachedManager);
						
						addMessage(
							"Added cached manager",
							cachedManager.toString(),
							LogMessage.LEVEL_INFO,
							LogMessage.IMPORTANCE_HIGH
						);
						
						SharedMain.sharedDispatcher.dispatchChanged(
							FlackEvent.CHANGED_MANAGER,
							cachedManager,
							FlackEvent.ACTION_CREATED
						);
					}
				}
				
				SharedMain.sharedDispatcher.dispatchChanged(
					FlackEvent.CHANGED_MANAGERS,
					null,
					FlackEvent.ACTION_POPULATED
				);
				
				super.afterComplete(addCompletedMessage);
			}
			else
				faultOnSuccess();
		}
	}
}