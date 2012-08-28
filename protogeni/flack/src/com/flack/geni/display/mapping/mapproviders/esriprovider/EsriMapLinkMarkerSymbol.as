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

package com.flack.geni.display.mapping.mapproviders.esriprovider
{
	import com.esri.ags.Graphic;
	import com.esri.ags.Map;
	import com.esri.ags.geometry.Geometry;
	import com.esri.ags.geometry.MapPoint;
	import com.esri.ags.symbols.MarkerSymbol;
	import com.esri.ags.symbols.Symbol;
	import com.flack.geni.resources.physical.PhysicalNodeCollection;
	import com.flack.geni.resources.sites.GeniManagerCollection;
	import com.flack.geni.resources.virtual.VirtualNodeCollection;
	import com.flack.shared.utils.ColorUtil;
	
	import flash.display.Sprite;
	import flash.events.MouseEvent;
	import flash.filters.DropShadowFilter;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	import flash.text.TextFormat;
	
	import mx.core.DragSource;
	import mx.core.IUIComponent;
	import mx.core.UIComponent;
	import mx.managers.DragManager;
	
	public class EsriMapLinkMarkerSymbol extends Symbol
	{
		private var marker:EsriMapLinkMarker;
		
		private var label:String;
		
		private var borderColor:Object;
		private var backgroundColor:Object;
		
		public function EsriMapLinkMarkerSymbol(newMarker:EsriMapLinkMarker,
												newLabel:String,
												edgeColor:Object,
												backColor:Object)
		{
			super();
			borderColor = edgeColor;
			backgroundColor = backColor;
			marker = newMarker;
			label = newLabel;
		}
		
		override public function clear(sprite:Sprite):void
		{
			removeAllChildren(sprite);
			sprite.graphics.clear();
			sprite.x = 0;
			sprite.y = 0;
			sprite.filters = [];
			sprite.buttonMode = false;
		}
		
		
		override public function destroy(sprite:Sprite):void
		{
			clear(sprite);
		}
		
		override public function draw(sprite:Sprite,
									  geometry:Geometry,
									  attributes:Object,
									  map:Map):void
		{
			if (geometry is MapPoint)
			{
				var mapPoint:MapPoint = MapPoint(geometry) as MapPoint;
				sprite.x = toScreenX(map, mapPoint.x)-52;
				sprite.y = toScreenY(map, mapPoint.y)-14;
				
				var textFormat:TextFormat = new TextFormat();
				textFormat.size = 15;
				var textField:TextField = new TextField();
				textField.defaultTextFormat = textFormat;
				textField.text = label;
				textField.selectable = false;
				textField.border = true;
				textField.borderColor = borderColor as uint;
				textField.background = true;
				textField.multiline = false;
				textField.autoSize = TextFieldAutoSize.CENTER;
				textField.backgroundColor = backgroundColor as uint;
				textField.mouseEnabled = false;
				textField.filters = [new DropShadowFilter()];
				
				var button:Sprite = new Sprite();
				button.buttonMode=true;
				button.useHandCursor = true;
				button.addChild(textField);
				
				sprite.addChild(button);
				
				sprite.buttonMode = true;
				sprite.useHandCursor = true;
			}
		}
	}
}