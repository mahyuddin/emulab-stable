/* GENIPUBLIC-COPYRIGHT
 * Copyright (c) 2008, 2009 University of Utah and the Flux Group.
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
  import flash.external.ExternalInterface;
  import flash.net.URLRequest;
  import flash.net.navigateToURL;
  
  import mx.collections.ArrayCollection;

  public class Util
  {
	  public static const defaultRspecVersion:Number = 0.2;
	  
	  public static function showSetup():void
	  {
		  navigateToURL(new URLRequest("https://www.protogeni.net/trac/protogeni/wiki/FlackManual#Setup"), "_blank");
	  }
	  public static function showManual():void
	  {
		  navigateToURL(new URLRequest("https://www.protogeni.net/trac/protogeni/wiki/FlackManual"), "_blank");
	  }
	  
	  public static function openWebsite(url:String):void
	  {
		  navigateToURL(new URLRequest(url), "_blank");
	  }
	  
	  public static function tryGetBaseUrl(url:String):String
	  {
		  var hostPattern:RegExp = /^(http(s?):\/\/([^\/]+))(\/.*)?$/;
		  var match : Object = hostPattern.exec(url);
		  if (match != null)
			  return match[1];
		  else
			  return url;
	  }
	  
    public static function makeUrn(authority : String,
                                   type : String,
                                   name : String) : String
    {
      return "urn:publicid:IDN+" + authority + "+" + type + "+" + name;
    }
	
	public static function getAuthorityFromUrn(urn:String) : String
	{
		return urn.split("+")[1];
	}
	
	public static function getNameFromUrn(urn:String) : String
	{
		return urn.split("+")[3];
	}
	
	// Takes the given bandwidth and creates a human readable string
	public static function kbsToString(bandwidth:Number):String {
		var bw:String = "";
		if(bandwidth < 1000) {
			return bandwidth + " Kb/s"
		} else if(bandwidth < 1000000) {
			return bandwidth / 1000 + " Mb/s"
		} else if(bandwidth < 1000000000) {
			return bandwidth / 1000000 + " Gb/s"
		}
		return bw;
	}
	
	// Makes the first letter uppercase
	public static function firstToUpper (phrase : String) : String {
		return phrase.substring(1, 0).toUpperCase()+phrase.substring(1);
	}
	
	public static function replaceString(original:String, find:String, replace:String):String {
		return original.split(find).join(replace);
	}
	
	public static function getDotString(name : String) : String {
		return replaceString(replaceString(name, ".", ""), "-", "");
	}
	
	public static function parseProtogeniDate(value:String):Date
	{
		var dateString:String = value;
		dateString = dateString.replace(/(\d{4,4})\-(\d{2,2})\-(\d{2,2})/g, "$1/$2/$3");
		dateString = dateString.replace("T", " ");
		dateString = dateString.replace(/(\+|\-)(\d+):(\d+)/g, " GMT$1$2$3");
		dateString = dateString.replace("Z", " GMT-0000");
		return new Date(Date.parse(dateString));
	}
	
	public static function addIfNonexistingToArray(source:Array, o:*):void
	{
		if(source.indexOf(o) == -1)
			source.push(o);
	}
	
	public static function addIfNonexistingToArrayCollection(source:ArrayCollection, o:*):void
	{
		if(source.getItemIndex(o) == -1)
			source.addItem(o);
	}
	
	public static function findInAny(text:Array, candidates:Array, matchAll:Boolean = false, caseSensitive:Boolean = false):Boolean
	{
		if(!caseSensitive)
		{
			for each(var textTemp:String in text)
			textTemp = textTemp.toLowerCase();
		}
			
		for each(var candidate:String in candidates)
		{
			if(!caseSensitive)
				candidate = candidate.toLowerCase();
			for each(var s:String in text)
			{
				
				if(matchAll)
				{
					if(candidate == s)
						return true;
				}
				else
				{
					if(candidate.indexOf(s) > -1)
						return true;
				}
			}
			
		}
		return false;
	}
	
	public static function areEqual(a:Array,b:Array):Boolean {
		// handle null arrays
		if(a == null && b == null)
			return true;
		else if(a == null || b == null)
			return false;
		
		// obviously not equal
		if(a.length != b.length) {
			return false;
		}
		
		var len:int = a.length;
		for(var i:int = 0; i < len; i++) {
			if(a[i] !== b[i]) {
				return false;
			}
		}
		return true;
	}
	
	public static function haveSame(a:Array,b:Array):Boolean {
		if(a.length != b.length)
			return false;
		
		var len:int = a.length;
		for(var i:int = 0; i < len; i++) {
			if(b.indexOf(a[i]) == -1)
				return false;
		}
		return true;
	}
	
	// Shortens the given string to a length, taking out from the middle
	public static function shortenString(phrase : String, size : int) : String {
		// Remove any un-needed elements
		var a:Array = phrase.split("https://");
		if(a.length == 1)
			a = phrase.split("http://");
		if(a.length == 2)
			phrase = a[1];
		
		if(phrase.length < size)
			return phrase;
		
		var removeChars:int = phrase.length - size + 3;
		var upTo:int = (phrase.length / 2) - (removeChars / 2);
		return phrase.substring(0, upTo) + "..." +  phrase.substring(upTo + removeChars);
	}
	
	public static  function getBrowserName():String
	{
		var browser:String;
		var browserAgent:String = ExternalInterface.call("function getBrowser(){return navigator.userAgent;}");
		
		if(browserAgent == null)
			return "Undefined";
		else if(browserAgent.indexOf("Firefox") >= 0)
			browser = "Firefox";
		else if(browserAgent.indexOf("Safari") >= 0)
			browser = "Safari";
		else if(browserAgent.indexOf("MSIE") >= 0)
			browser = "IE";
		else if(browserAgent.indexOf("Opera") >= 0)
			browser = "Opera";
		else
			browser = "Undefined";
		
		return (browser);
	}
	
	public static function keepUniqueObjects(ac:ArrayCollection, oc:ArrayCollection = null):ArrayCollection
	{
		var newAc:ArrayCollection;
		if(oc != null)
			newAc = oc;
		else
			newAc = new ArrayCollection();
		for each(var o:Object in ac) {
			if(o is ArrayCollection)
				newAc = keepUniqueObjects((o as ArrayCollection), newAc);
			else {
				if(!newAc.contains(o))
					newAc.addItem(o);
			}
		}
		return newAc;
	}
  }
}
