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
	import com.esri.ags.geometry.WebMercatorMapPoint;
	import com.flack.geni.display.mapping.GeniMapNodeMarker;
	import com.flack.geni.display.mapping.LatitudeLongitude;
	import com.flack.geni.resources.physical.PhysicalLocation;
	import com.flack.geni.resources.physical.PhysicalLocationCollection;
	import com.flack.geni.resources.physical.PhysicalNodeCollection;
	import com.flack.geni.resources.virtual.VirtualNodeCollection;
	
	import flash.events.MouseEvent;
	
	import mx.controls.Alert;
	import mx.core.DragSource;
	import mx.events.DragEvent;
	import mx.managers.DragManager;
	
	public class EsriMapNodeMarker extends Graphic implements GeniMapNodeMarker
	{
		public var locations:PhysicalLocationCollection;
		public var location:PhysicalLocation;
		
		private var nodes:*;
		public function get Nodes():*
		{
			return nodes;
		}
		public function set Nodes(value:*):void
		{
			nodes = value;
		}
		
		public var mapPoint:WebMercatorMapPoint;
		
		private var allowDragging:Boolean = false;
		
		public function EsriMapNodeMarker(newLocations:PhysicalLocationCollection,
										  newNodes:*)
		{
			var newLocation:PhysicalLocation;
			if(newLocations.length > 1)
				newLocation = newLocations.Middle;
			else
				newLocation = newLocations.collection[0];
			
			var newMapPoint:WebMercatorMapPoint = new WebMercatorMapPoint(newLocation.longitude, newLocation.latitude);
			
			super(newMapPoint);
			attributes = {marker: this};
			
			mapPoint = newMapPoint;
			Nodes = newNodes;
			location = newLocation;
			locations = newLocations;
			
			symbol = new EsriMapNodeMarkerSymbol(this);
			
			addEventListener(MouseEvent.MOUSE_MOVE, drag);
			addEventListener(MouseEvent.MOUSE_DOWN, mouseDown);
			addEventListener(MouseEvent.ROLL_OUT, mouseExit);
		}
		
		public function destroy():void
		{
			removeEventListener(MouseEvent.MOUSE_MOVE, drag);
			removeEventListener(MouseEvent.MOUSE_DOWN, mouseDown);
			removeEventListener(MouseEvent.ROLL_OUT, mouseExit);
		}
		
		private function mouseDown(event:MouseEvent):void
		{
			allowDragging = true;
		}
		
		private function mouseExit(event:MouseEvent):void
		{
			allowDragging = false;
		}
		
		public function drag(e:MouseEvent):void
		{
			if(allowDragging)
			{
				var ds:DragSource = new DragSource();
				if(nodes is PhysicalNodeCollection)
					ds.addData(this, 'physicalMarker');
				else if(nodes is VirtualNodeCollection)
					ds.addData(this, 'virtualMarker');
				DragManager.doDrag(this, ds, e, (symbol as EsriMapNodeMarkerSymbol).getCopy());
			}
		}
		
		public function t(e:MouseEvent):void
		{
			e.stopPropagation();
			Alert.show("test");
		}
		
		public function get Visible():Boolean
		{
			return visible;
		}
		
		public function get LatitudeLongitudeLocation():LatitudeLongitude
		{
			return new LatitudeLongitude(location.latitude, location.longitude);
		}
		
		public function sameLocationAs(testLocations:Vector.<PhysicalLocation>):Boolean
		{
			if(testLocations.length != locations.length)
				return false;
			for each(var testLocation:PhysicalLocation in testLocations)
			{
				if(!locations.contains(testLocation))
					return false;
			}
			return true;
		}
		
		public function setLook(newNodes:*):void
		{
			// Don't redo marker
			if(nodes != null && newNodes.sameAs(nodes))
				return;
			
			nodes = newNodes;
		}
		
		public function hide():void
		{
			visible = false;
		}
		
		public function show():void
		{
			visible = true;
		}
	}
}