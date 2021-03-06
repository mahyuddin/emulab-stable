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

package com.flack.geni.tasks.groups.slice
{
	import com.flack.geni.resources.virt.Slice;
	import com.flack.geni.tasks.xmlrpc.protogeni.sa.GetSliceCredentialSaTask;
	import com.flack.geni.tasks.xmlrpc.protogeni.sa.ResolveSliceSaTask;
	import com.flack.shared.tasks.ParallelTaskGroup;
	
	/**
	 * Resolves all information about existing slices
	 * 
	 * @author mstrum
	 * 
	 */
	public final class ResolveSliceTaskGroup extends ParallelTaskGroup
	{
		public var slice:Slice;
		/**
		 * 
		 * @param taskSlice Slice to get everything for
		 * @param shouldResolveSlice Resolve the slice?
		 * @param shouldQueryAllManagers Query all managers? Needed if resources exist at non-ProtoGENI managers.
		 * 
		 */
		public function ResolveSliceTaskGroup(newSlice:Slice)
		{
			super(
				"Resolve " + newSlice.Name,
				"Resolves all information for the slice: " + newSlice.id.full
			);
			relatedTo.push(newSlice);
			slice = newSlice;
		}
		
		override protected function runStart():void
		{
			if(tasks.length == 0)
			{
				add(new ResolveSliceSaTask(slice));
				add(new GetSliceCredentialSaTask(slice));
			}
			
			super.runStart();
		}
	}
}