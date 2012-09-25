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

package com.flack.geni.tasks.xmlrpc.am
{
	import com.flack.geni.resources.virtual.Sliver;
	import com.flack.shared.FlackEvent;
	import com.flack.shared.SharedMain;
	import com.flack.shared.logging.LogMessage;
	import com.flack.shared.tasks.TaskError;
	import com.flack.shared.utils.DateUtil;
	import com.flack.shared.utils.StringUtil;
	
	import mx.controls.Alert;
	
	/**
	 * Renews the sliver until the given date.
	 * 
	 * @author mstrum
	 * 
	 */
	public final class RenewTask extends AmXmlrpcTask
	{
		public var sliver:Sliver;
		public var newExpires:Date;
		
		/**
		 * 
		 * @param renewSliver Sliver to renew
		 * @param newExpirationDate Desired expiration date
		 * 
		 */
		public function RenewTask(renewSliver:Sliver,
								  newExpirationDate:Date)
		{
			super(
				renewSliver.manager.api.url,
				renewSliver.manager.api.version < 3
					? AmXmlrpcTask.METHOD_RENEWSLIVER : AmXmlrpcTask.METHOD_RENEW,
				renewSliver.manager.api.version,
				"Renew @ " + renewSliver.manager.hrn,
				"Renewing on " + renewSliver.manager.hrn + " on slice named " + renewSliver.slice.hrn,
				"Renew"
			);
			relatedTo.push(renewSliver);
			relatedTo.push(renewSliver.slice);
			relatedTo.push(renewSliver.manager);
			sliver = renewSliver;
			newExpires = newExpirationDate;
		}
		
		override protected function createFields():void
		{
			addOrderedField(sliver.slice.id.full);
			addOrderedField([sliver.slice.credential.Raw]);
			addOrderedField(DateUtil.toRFC3339(newExpires));
			if(apiVersion > 1)
				addOrderedField({});
		}
		
		override protected function afterComplete(addCompletedMessage:Boolean=false):void
		{
			// Sanity check for AM API 2+
			if(apiVersion > 1)
			{
				if(genicode != AmXmlrpcTask.GENICODE_SUCCESS)
				{
					faultOnSuccess();
					return;
				}
			}
			
			try
			{
				if(data == true)
				{
					sliver.expires = newExpires;
					
					SharedMain.sharedDispatcher.dispatchChanged(
						FlackEvent.CHANGED_SLIVER,
						sliver
					);
					SharedMain.sharedDispatcher.dispatchChanged(
						FlackEvent.CHANGED_SLICE,
						sliver.slice
					);
					
					addMessage(
						"Renewed",
						"Renewed, sliver expires in " + DateUtil.getTimeUntil(sliver.expires),
						LogMessage.LEVEL_INFO,
						LogMessage.IMPORTANCE_HIGH
					);
					
					super.afterComplete(addCompletedMessage);
				}
				else if(data == false)
				{
					Alert.show("Failed to renew sliver @ " + sliver.manager.hrn);
					afterError(
						new TaskError(
							"Renew failed",
							TaskError.CODE_PROBLEM
						)
					);
				}
				else
				{
					afterError(
						new TaskError(
							"Renew failed. Received incorrect data",
							TaskError.CODE_UNEXPECTED
						)
					);
				}
			}
			catch(e:Error)
			{
				afterError(
					new TaskError(
						StringUtil.errorToString(e),
						TaskError.CODE_UNEXPECTED,
						e
					)
				);
			}
		}
	}
}