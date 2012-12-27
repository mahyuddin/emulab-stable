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

package com.flack.geni.tasks.xmlrpc.protogeni.cm
{
	import com.flack.geni.resources.virtual.AggregateSliver;
	import com.flack.geni.tasks.xmlrpc.protogeni.ProtogeniXmlrpcTask;
	import com.flack.shared.logging.LogMessage;
	
	/**
	 * Restarts all resources in the sliver
	 * 
	 * @author mstrum
	 * 
	 */
	public final class RestartSliverCmTask extends ProtogeniXmlrpcTask
	{
		public var sliver:AggregateSliver;
		
		/**
		 * 
		 * @param newSliver Sliver to restart resources for
		 * 
		 */
		public function RestartSliverCmTask(newSliver:AggregateSliver)
		{
			super(
				newSliver.manager.url,
				ProtogeniXmlrpcTask.MODULE_CM,
				ProtogeniXmlrpcTask.METHOD_RESTARTSLIVER,
				"Restart sliver @ " + newSliver.manager.hrn,
				"Restarts sliver on " + newSliver.manager.hrn + " for slice named " + newSliver.slice.Name,
				"Restart Sliver"
			);
			relatedTo.push(newSliver);
			relatedTo.push(newSliver.slice);
			relatedTo.push(newSliver.manager);
			sliver = newSliver;
		}
		
		override protected function createFields():void
		{
			addNamedField("slice_urn", sliver.slice.id.full);
			addNamedField("credentials", [sliver.slice.credential.Raw]);
		}
		
		override protected function afterComplete(addCompletedMessage:Boolean=false):void
		{
			if(code == ProtogeniXmlrpcTask.CODE_SUCCESS)
			{
				addMessage(
					"Restarted",
					"Sliver was restarted",
					LogMessage.LEVEL_INFO,
					LogMessage.IMPORTANCE_HIGH
				);
				
				super.afterComplete(addCompletedMessage);
			}
			else
				faultOnSuccess();
		}
	}
}