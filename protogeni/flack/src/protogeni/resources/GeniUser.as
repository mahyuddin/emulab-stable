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

package protogeni.resources
{
	import com.mattism.http.xmlrpc.JSLoader;

	/**
	 * GENI user
	 * 
	 * @author mstrum
	 * 
	 */
	public class GeniUser
	{
		[Bindable]
		public var uid:String;
		
		[Bindable]
		public var hrn:String;
		[Bindable]
		public var email:String;
		[Bindable]
		public var name:String;
		[Bindable]
		public var authority:SliceAuthority;
		public var userCredential:String = "";
		public var keys:Vector.<Key> = new Vector.<Key>();
		[Bindable]
		public var urn:IdnUrn;
		
		public var slices:SliceCollection;
		
		public var hasSetupJavascript:Boolean = false;
		
		public var sliceCredential:String = "";
		
		public var passwd:String = "";
		
		public function get Credential():String {
			if(userCredential != null && userCredential.length > 0)
				return userCredential;
			if(sliceCredential != null && sliceCredential.length > 0)
				return sliceCredential;
			return "";
		}
		
		public function GeniUser()
		{
			slices = new SliceCollection();
		}
		
		public function setPassword(password:String,
									store:Boolean):Boolean {
			this.passwd = password;
			if(store) {
				if(FlackCache.userPassword != password) {
					FlackCache.userPassword = password;
					FlackCache.saveBasic();
				}
			} else if(FlackCache.userPassword.length > 0) {
				FlackCache.userPassword = "";
				FlackCache.saveBasic();
			}
			return tryToSetInJavascript(password);
		}
		
		public function tryToSetInJavascript(password:String):Boolean {
			if(Main.useJavascript) {
				if(password.length > 0 && FlackCache.userSslPem.length > 0) {
					try {
						JSLoader.setClientInfo(password, FlackCache.userSslPem);
						hasSetupJavascript = true;
					} catch ( e:Error) {
						LogHandler.appendMessage(new LogMessage("JS", "JS User Cert", e.toString(), true, LogMessage.TYPE_END));
						return false;
					}
				} else
					return false;
			}
			return true;
		}
	}
}