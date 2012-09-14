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

package com.flack.geni.resources.sites.managers
{
	import com.flack.geni.resources.sites.GeniManager;
	import com.flack.geni.resources.sites.SupportedLinkType;
	import com.flack.geni.resources.virtual.LinkType;
	import com.flack.shared.resources.sites.ApiDetails;
	import com.flack.shared.resources.sites.FlackManager;

	/**
	 * Federated ProtoGENI manager
	 * 
	 * @author mstrum
	 * 
	 */
	public class ProtogeniComponentManager extends GeniManager
	{
		/**
		 * 
		 * @param newId IDN-URN
		 * 
		 */
		public function ProtogeniComponentManager(newId:String)
		{
			super(FlackManager.TYPE_PROTOGENI, ApiDetails.API_PROTOGENI, newId);
		}
		
		override public function makeValidClientIdFor(value:String):String
		{
			return value.replace(".", "");
		}
		
		override public function setApi(details:ApiDetails):void
		{
			api = details;
			if(api.url.length == 0)
			{
				api.url = url;
				if(api.type == ApiDetails.API_GENIAM)
					api.url += "/am";
			}
		}
	}
}