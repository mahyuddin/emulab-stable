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
	import com.flack.geni.display.mapping.GeniMap;
	import com.flack.geni.display.mapping.GeniMapHandler;
	import com.flack.geni.display.mapping.mapproviders.esriprovider.EsriMap;
	import com.flack.geni.display.windows.StartWindow;
	import com.flack.geni.plugins.Plugin;
	import com.flack.geni.plugins.emulab.Emulab;
	import com.flack.geni.plugins.instools.Instools;
	import com.flack.geni.plugins.openflow.Openflow;
	import com.flack.geni.plugins.planetlab.Planetlab;
	import com.flack.geni.resources.sites.authorities.ProtogeniSliceAuthority;
	import com.flack.geni.resources.virtual.Slice;
	import com.flack.geni.tasks.groups.GetCertBundlesTaskGroup;
	import com.flack.geni.tasks.http.PublicListAuthoritiesTask;
	import com.flack.shared.SharedMain;
	import com.flack.shared.display.areas.MapContent;
	import com.flack.shared.resources.docs.RspecVersion;
	import com.flack.shared.resources.docs.RspecVersionCollection;
	
	import mx.core.FlexGlobals;
	import mx.core.IVisualElement;
	
	/**
	 * Global container for things we use
	 * 
	 * @author mstrum
	 * 
	 */
	public class GeniMain
	{
		public static const becomeUserUrl:String = "http://www.protogeni.net/trac/protogeni/wiki/FlackManual#BecomingaUser";
		public static const manualUrl:String = "http://www.protogeni.net/trac/protogeni/wiki/FlackManual";
		public static const tutorialUrl:String = "https://www.protogeni.net/trac/protogeni/wiki/FlackTutorial";
		public static const sshKeysSteps:String = "http://www.protogeni.net/trac/protogeni/wiki/Tutorial#UploadingSSHKeys";
		
		// Portal
		public static var securityPreset:Boolean = false;
		public static var loadAllManagers:Boolean = false;
		public static var useSa:ProtogeniSliceAuthority = null;
		public static var useSlice:Slice = null;
		public static var chUrl:String = "";
		
		// Tutorial
		public static var rspecListUrl:String = "";
		[Bindable]
		public static var viewList:Boolean = false;
		
		public static function preinitMode():void
		{
			GeniMain.geniUniverse = new GeniUniverse();
		}
		
		public static var mapper:GeniMapHandler;
		public static function initMode():void
		{
			var map:GeniMap = new EsriMap();
			var mapContent:MapContent = new MapContent();
			FlexGlobals.topLevelApplication.contentAreaGroup.Root = mapContent;
			mapContent.addElement(map as IVisualElement);
			
			mapper = new GeniMapHandler(map);
		}
		
		public static function initPlugins():void
		{
			plugins = new Vector.<Plugin>();
			plugins.push(new Instools());
			plugins.push(new Emulab());
			plugins.push(new Planetlab());
			plugins.push(new Openflow());
			// Add new plugins
			for each(var plugin:Plugin in plugins)
				plugin.init();
		}
		
		public static function runFirst():void
		{
			if(securityPreset)
			{
				geniUniverse.loadAuthenticated();
			}
			else
			{
				// Initial tasks
				if(SharedMain.Bundle.length == 0)
					SharedMain.tasker.add(new GetCertBundlesTaskGroup());
				if(GeniMain.geniUniverse.authorities.length == 0)
					SharedMain.tasker.add(new PublicListAuthoritiesTask());
				
				// Load initial window
				var startWindow:StartWindow = new StartWindow();
				startWindow.showWindow(true, true);
			}
			
		}
		
		[Bindable]
		/**
		 * 
		 * @return GENI Universe containing everything GENI related
		 * 
		 */
		public static var geniUniverse:GeniUniverse;
		
		/**
		 * Plugins which are loaded
		 */
		public static var plugins:Vector.<Plugin>;
		
		/**
		 * RSPEC versions Flack knows how to parse or generate
		 */
		public static var usableRspecVersions:RspecVersionCollection = new RspecVersionCollection(
			[
				new RspecVersion(RspecVersion.TYPE_PROTOGENI, 0.1),
				new RspecVersion(RspecVersion.TYPE_PROTOGENI, 0.2),
				new RspecVersion(RspecVersion.TYPE_PROTOGENI, 2),
				new RspecVersion(RspecVersion.TYPE_GENI, 3)
			]
		);
		
		public static function get MapKey():String
		{
			try
			{
				if(FlexGlobals.topLevelApplication.parameters.mapkey != null)
					return FlexGlobals.topLevelApplication.parameters.mapkey;
			}
			catch(all:Error)
			{
			}
			return "";
		}
		
		public static function preloadParams():void
		{
			/*
			try{
			if(FlexGlobals.topLevelApplication.parameters.mapkey != null)
			{
			Main.Application().forceMapKey = FlexGlobals.topLevelApplication.parameters.mapkey;
			}
			} catch(all:Error) {
			}
			
			try{
			if(FlexGlobals.topLevelApplication.parameters.debug != null)
			{
			Main.debugMode = FlexGlobals.topLevelApplication.parameters.debug == "1";
			}
			} catch(all:Error) {
			}
			
			try{
			if(FlexGlobals.topLevelApplication.parameters.pgonly != null)
			{
			Main.protogeniOnly = FlexGlobals.topLevelApplication.parameters.pgonly == "1";
			}
			} catch(all:Error) {
			}
			*/
		}
		
		public static function loadParams():void
		{
			// External examples
			try{
				if(FlexGlobals.topLevelApplication.parameters.rspeclisturl != null)
				{
					rspecListUrl = FlexGlobals.topLevelApplication.parameters.rspeclisturl;
					viewList = true;
				}
			} catch(all:Error) {
			}
			
			// Portal
			try{
				if(FlexGlobals.topLevelApplication.parameters.securitypreset != null)
				{
					securityPreset = FlexGlobals.topLevelApplication.parameters.securitypreset == "1";
					geniUniverse.user.hasSetupSecurity = true;
				}
			} catch(all:Error) {
			}
			try{
				if(FlexGlobals.topLevelApplication.parameters.loadallmanagers != null)
				{
					loadAllManagers = FlexGlobals.topLevelApplication.parameters.loadallmanagers == "1";
				}
			} catch(all:Error) {
			}
			try{
				if(FlexGlobals.topLevelApplication.parameters.saurl != null && FlexGlobals.topLevelApplication.parameters.saurn != null)
				{
					useSa = new ProtogeniSliceAuthority(FlexGlobals.topLevelApplication.parameters.saurn, FlexGlobals.topLevelApplication.parameters.saurl);
					geniUniverse.user.authority = useSa;
					geniUniverse.authorities.add(useSa);
				}
			} catch(all:Error) {
			}
			try{
				if(FlexGlobals.topLevelApplication.parameters.churl != null)
				{
					chUrl = FlexGlobals.topLevelApplication.parameters.churl;
					geniUniverse.clearinghouse.url = chUrl;
				}
			} catch(all:Error) {
			}
			try{
				if(FlexGlobals.topLevelApplication.parameters.sliceurn != null)
				{
					useSlice = new Slice(FlexGlobals.topLevelApplication.parameters.sliceurn);
					useSlice.authority = geniUniverse.user.authority;
					useSlice.creator = geniUniverse.user;
					geniUniverse.user.slices.add(useSlice);
				}
			} catch(all:Error) {
			}
			
			/*
			try{
			if(FlexGlobals.topLevelApplication.parameters.mode != null)
			{
			var input:String = FlexGlobals.topLevelApplication.parameters.mode;
			
			Main.Application().allowAuthenticate = input != "publiconly";
			Main.geniHandler.unauthenticatedMode = input != "authenticate";
			}
			} catch(all:Error) {
			}
			try{
			if(FlexGlobals.topLevelApplication.parameters.saurl != null)
			{
			for each(var sa:ProtogeniSliceAuthority in Main.geniHandler.GeniAuthorities.source) {
			if(sa.Url == FlexGlobals.topLevelApplication.parameters.saurl) {
			Main.geniHandler.forceAuthority = sa;
			break;
			}
			}
			}
			} catch(all:Error) {
			}
			try{
			if(FlexGlobals.topLevelApplication.parameters.publicurl != null)
			{
			Main.geniHandler.publicUrl = FlexGlobals.topLevelApplication.parameters.publicurl;
			}
			} catch(all:Error) {
			}
			*/
		}
	}
}
