﻿/* GENIPUBLIC-COPYRIGHT
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

package protogeni.communication
{
  import flash.utils.ByteArray;
  
  import mx.utils.Base64Decoder;
  
  import protogeni.Util;
  import protogeni.resources.GeniManager;
  import protogeni.resources.ProtogeniComponentManager;

  public class RequestDiscoverResourcesPublic extends Request
  {
	  
    public function RequestDiscoverResourcesPublic(newCm:ProtogeniComponentManager) : void
    {
		super("DiscoverResourcesPublic (" + Util.shortenString(newCm.Url, 15) + ")", "Publicly discovering resources for " + newCm.Url, null, true, true, false);
		cm = newCm;
		op.setExactUrl(newCm.Url);
		op.type = Operation.HTTP;
		cm.lastRequest = this;
	}
	
	override public function complete(code : Number, response : Object) : *
	{
		if (code == CommunicationUtil.GENIRESPONSE_SUCCESS)
		{
			var rspec:String = response as String;
			if(rspec.charAt(0) != '<') {
				var decodor:Base64Decoder = new Base64Decoder();
				decodor.decode(rspec);
				var bytes:ByteArray = decodor.toByteArray();
				bytes.uncompress();
				rspec = bytes.toString();
			}
			cm.Rspec = new XML(rspec);
			cm.rspecProcessor.processResourceRspec(cleanup);
		}
		else
		{
			cm.Status = GeniManager.STATUS_FAILED;
			this.removeImmediately = true;
			Main.geniDispatcher.dispatchGeniManagerChanged(cm);
		}
		
		return null;
	}
	
	override public function cancel():void
	{
		cm.Status = GeniManager.STATUS_UNKOWN;
		Main.geniDispatcher.dispatchGeniManagerChanged(cm);
		op.cleanup();
	}
	
	override public function cleanup():void
	{
		running = false;
		if(cm.Status == GeniManager.STATUS_INPROGRESS)
			cm.Status = GeniManager.STATUS_FAILED;
		Main.geniHandler.requestHandler.remove(this, false);
		Main.geniDispatcher.dispatchGeniManagerChanged(cm);
		op.cleanup();
		Main.geniHandler.mapHandler.drawMap();
		if(cm.Status == GeniManager.STATUS_VALID)
			Main.Application().setStatus("Parsing " + cm.Hrn + " RSPEC Done",false);
		Main.geniHandler.requestHandler.tryNext();
	}

    private var cm : ProtogeniComponentManager;
  }
}