/*
 * Copyright (c) 2008-2013 University of Utah and the Flux Group.
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

package com.flack.geni.resources.virt
{
	import com.flack.geni.resources.Extensions;

	/**
	 * Link type
	 * @author mstrum
	 * 
	 */
	public class LinkType
	{
		public static const LAN_V1:String = "ethernet";
		public static const LAN_V2:String = "lan";
		public static const GRETUNNEL_V1:String = "tunnel";
		public static const GRETUNNEL_V2:String = "gre-tunnel";
		public static const ION:String = "ion";
		public static const GPENI:String = "gpeni";
		public static const VLAN:String = "VLAN";
		public static const STITCHED:String = "";
		
		public var name:String;
		public var extensions:Extensions = new Extensions();
		
		/**
		 * 
		 * @param newName Name of the link type
		 * 
		 */
		public function LinkType(newName:String = STITCHED)
		{
			name = newName;
		}
	}
}