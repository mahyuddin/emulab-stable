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

package com.flack.geni.tasks.xmlrpc.am
{
	import com.flack.geni.GeniMain;
	import com.flack.geni.resources.virtual.Sliver;
	import com.flack.geni.tasks.process.GenerateRequestManifestTask;
	import com.flack.geni.tasks.process.ParseRequestManifestTask;
	import com.flack.shared.FlackEvent;
	import com.flack.shared.SharedMain;
	import com.flack.shared.logging.LogMessage;
	import com.flack.shared.resources.docs.Rspec;
	import com.flack.shared.tasks.Task;
	import com.flack.shared.tasks.TaskError;
	import com.flack.shared.utils.StringUtil;
	
	/**
	 * Provision resources
	 * 
	 * AM v3+
	 * 
	 * @author mstrum
	 * 
	 */
	public final class ProvisionTask extends AmXmlrpcTask
	{
		public var sliver:Sliver;
		public var request:Rspec;
		
		/**
		 * 
		 * @param newSliver Sliver to allocate resources in
		 * @param newRspec RSPEC to send
		 * 
		 */
		public function ProvisionTask(newSliver:Sliver,
									 newRspec:Rspec = null)
		{
			super(
				newSliver.manager.api.url,
				AmXmlrpcTask.METHOD_PROVISION,
				newSliver.manager.api.version,
				"Allocate @ " + newSliver.manager.hrn,
				"Allocate on aggregate manager " + newSliver.manager.hrn + " for slice named " + newSliver.slice.hrn,
				"Allocate"
			);
			relatedTo.push(newSliver);
			relatedTo.push(newSliver.slice);
			relatedTo.push(newSliver.manager);
			
			sliver = newSliver;
			request = newRspec;
			
			addMessage(
				"Waiting to create...",
				"A sliver will be created at " + sliver.manager.hrn,
				LogMessage.LEVEL_INFO,
				LogMessage.IMPORTANCE_HIGH
			);
		}
		
		override protected function runStart():void
		{
			sliver.markStaged();
			sliver.manifest = null;
			
			// Generate a rspec if needed
			if(request == null)
			{
				var generateNewRspec:GenerateRequestManifestTask = new GenerateRequestManifestTask(sliver, true, false, false);
				generateNewRspec.start();
				if(generateNewRspec.Status != Task.STATUS_SUCCESS)
				{
					afterError(generateNewRspec.error);
					return;
				}
				request = generateNewRspec.resultRspec;
				addMessage(
					"Generated request",
					request.document,
					LogMessage.LEVEL_INFO,
					LogMessage.IMPORTANCE_HIGH
				);
			}
			
			super.runStart();
		}
		
		override protected function createFields():void
		{
			addOrderedField(sliver.slice.id.full);
			addOrderedField([sliver.slice.credential.Raw]);
			addOrderedField(request.document);
			var userKeys:Array = [];
			for each(var key:String in sliver.slice.creator.keys)
				userKeys.push(key);
			addOrderedField(
				[
					{
						urn:GeniMain.geniUniverse.user.id.full,
						keys:userKeys
					}
				]
			);
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
				sliver.manifest = new Rspec(data,null,null,null, Rspec.TYPE_MANIFEST);
				
				addMessage(
					"Manifest received",
					data,
					LogMessage.LEVEL_INFO,
					LogMessage.IMPORTANCE_HIGH
				);
				
				parent.add(new ParseRequestManifestTask(sliver, sliver.manifest, false, true));
				
				super.afterComplete(addCompletedMessage);
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
		
		override protected function afterError(taskError:TaskError):void
		{
			sliver.status = Sliver.STATUS_FAILED;
			SharedMain.sharedDispatcher.dispatchChanged(
				FlackEvent.CHANGED_SLIVER,
				sliver,
				FlackEvent.ACTION_STATUS
			);
			
			super.afterError(taskError);
		}
		
		override protected function runCancel():void
		{
			sliver.status = Sliver.STATUS_UNKNOWN;
			SharedMain.sharedDispatcher.dispatchChanged(
				FlackEvent.CHANGED_SLIVER,
				sliver,
				FlackEvent.ACTION_STATUS
			);
		}
	}
}