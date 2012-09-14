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

package com.flack.geni
{
	/**
	 * Common XML values/function used around the library
	 * 
	 * @author mstrum
	 * 
	 */
	public final class RspecUtil
	{
		// RSPEC namespaces
		public static const rspec01Namespace:String = "http://www.protogeni.net/resources/rspec/0.1";
		public static const rspec01MalformedNamespace:String = "http://protogeni.net/resources/rspec/0.1";
		public static const rspec02Namespace:String = "http://www.protogeni.net/resources/rspec/0.2";
		public static const rspec02MalformedNamespace:String = "http://protogeni.net/resources/rspec/0.2";
		public static const rspec2Namespace:String = "http://www.protogeni.net/resources/rspec/2";
		public static const rspec3Namespace:String = "http://www.geni.net/resources/rspec/3";
		
		// Namespaces with prefixes
		public static var xsiNamespace:Namespace = new Namespace("xsi", "http://www.w3.org/2001/XMLSchema-instance");
		public static var flackNamespace:Namespace = new Namespace("flack", "http://www.protogeni.net/resources/rspec/ext/flack/1");
		public static var clientNamespace:Namespace = new Namespace("client", "http://www.protogeni.net/resources/rspec/ext/client/1");
		public static var historyNamespace:Namespace = new Namespace("history", "http://www.protogeni.net/resources/rspec/ext/history/1");
		public static var emulabNamespace:Namespace = new Namespace("emulab", "http://www.protogeni.net/resources/rspec/ext/emulab/1");
		public static var sharedVlanNamespace:Namespace = new Namespace("vlan", "http://www.protogeni.net/resources/rspec/ext/shared-vlan/1");
		public static var stitchingNamespace:Namespace = new Namespace("stitching", "http://hpn.east.isi.edu/rspec/ext/stitch/0.1/");
		
		
		public static function isKnownNamespace(uri:String):Boolean
		{
			switch(uri)
			{
				case rspec01Namespace:
				case rspec02Namespace:
				case rspec02MalformedNamespace:
				case rspec2Namespace:
				case rspec3Namespace:
				case xsiNamespace.uri:
				case flackNamespace.uri:
				case clientNamespace.uri:
					return true;
				default:
					return false;
			}
		}
		
		public static function getNamespaceForRspecVersion(version:Number):String
		{
			switch(version)
			{
				case 0.1:
					return rspec01Namespace;
				case 0.2:
					return rspec02Namespace;
				case 2:
					return rspec2Namespace;
				case 3:
					return rspec3Namespace;
				default:
					return "";
			}
		}
		
		// Schemas
		public static const rspec01SchemaLocation:String = "http://www.protogeni.net/resources/rspec/0.1 http://www.protogeni.net/resources/rspec/0.1/request.xsd";
		public static const rspec02SchemaLocation:String = "http://www.protogeni.net/resources/rspec/0.2 http://www.protogeni.net/resources/rspec/0.2/request.xsd";
		public static const rspec2SchemaLocation:String = "http://www.protogeni.net/resources/rspec/2 http://www.protogeni.net/resources/rspec/2/request.xsd";
		public static const rspec3SchemaLocation:String = "http://www.geni.net/resources/rspec/3 http://www.geni.net/resources/rspec/3/request.xsd";
	}
}