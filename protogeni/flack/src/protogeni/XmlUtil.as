/* GENIPUBLIC-COPYRIGHT
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

package protogeni
{
	/**
	 * Common XML values/function used around the library
	 * 
	 * @author mstrum
	 * 
	 */
	public final class XmlUtil
	{
		// Namespaces
		public static const rspec01Namespace:String = "http://www.protogeni.net/resources/rspec/0.1";
		public static const rspec02Namespace:String = "http://www.protogeni.net/resources/rspec/0.2";
		public static const rspec02MalformedNamespace:String = "http://protogeni.net/resources/rspec/0.2";
		public static const rspec2Namespace:String = "http://www.protogeni.net/resources/rspec/2";
		
		public static var xsiNamespace:Namespace = new Namespace("xsi", "http://www.w3.org/2001/XMLSchema-instance");
		
		public static var delayNamespace:Namespace = new Namespace("delay", "http://www.protogeni.net/resources/rspec/ext/delay/1");
		
		public static var flackNamespace:Namespace = new Namespace("flack", "http://www.protogeni.net/resources/rspec/ext/flack/1");
		
		public static var planetlabNamespace:Namespace = new Namespace("planetlab", "http://www.planet-lab.org/resources/ext/planetlab/1");
		
		public static function isKnownNamespace(ns:Namespace):Boolean {
			switch(ns.uri) {
				case rspec01Namespace:
				case rspec02Namespace:
				case rspec2Namespace:
				case xsiNamespace.uri:
				case flackNamespace.uri:
				case delayNamespace.uri:
				case planetlabNamespace.uri:
					return true;
				default:
					return false;
			}
		}
		
		// Schemas
		public static const rspec01SchemaLocation:String = "http://www.protogeni.net/resources/rspec/0.1 http://www.protogeni.net/resources/rspec/0.1/request.xsd";
		public static const rspec02SchemaLocation:String = "http://www.protogeni.net/resources/rspec/0.2 http://www.protogeni.net/resources/rspec/0.2/request.xsd";
		public static const rspec2SchemaLocation:String = "http://www.protogeni.net/resources/rspec/2 http://www.protogeni.net/resources/rspec/2/request.xsd";
		
		public static const delaySchemaLocation:String = "http://www.protogeni.net/resources/rspec/ext/delay/1 http://www.protogeni.net/resources/rspec/ext/delay/1/request-delay.xsd";
	}
}