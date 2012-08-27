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

package com.flack.geni.resources.virtual
{
	import com.flack.shared.resources.IdentifiableObject;
	import com.flack.shared.resources.IdnUrn;
	
	public class ComponentHop extends IdentifiableObject
	{
		public var nodeUrn:IdnUrn;
		public var interfaceId:String;
		
		public function ComponentHop(newId:String="", newNodeUrn:String="", newInterfaceId:String="")
		{
			super(newId);
			nodeUrn = new IdnUrn(newNodeUrn);
			interfaceId = newInterfaceId;
		}
	}
}