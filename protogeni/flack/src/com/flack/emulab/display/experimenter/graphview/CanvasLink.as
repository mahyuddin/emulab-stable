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

package com.flack.emulab.display.experimenter.graphview
{
	import com.flack.emulab.resources.virtual.VirtualLink;
	
	import flash.display.CapsStyle;
	import flash.display.LineScaleMode;
	import flash.display.Sprite;
	import flash.filters.DropShadowFilter;
	import flash.filters.GlowFilter;
	import flash.geom.Point;
	
	import mx.core.UIComponent;
	
	/**
	 * VirtualLink for use on the slice canvas
	 * 
	 * @author mstrum
	 * 
	 */
	public final class CanvasLink extends UIComponent
	{
		public static const DARK_COLOR:uint = 0xCC33CC;
		public static const LIGHT_COLOR:uint = 0x000000;
		
		public var link:VirtualLink;
		public var canvas:ExperimentCanvas;
		
		private var rawSprite:Sprite;
		
		public var button:CanvasLinkLabel;
		public var buttons:Vector.<CanvasBranchLabel>;
		public function getButtonFor(cn:CanvasNode):CanvasBranchLabel
		{
			for each(var bl:CanvasBranchLabel in buttons)
			{
				if(bl.iface.node == cn.Node)
					return bl;
			}
			return null;
		}
		
		public function setFilters(newFilters:Array):void
		{
			rawSprite.filters = newFilters;
			button.setFilters(newFilters);
			for each(var bl:CanvasBranchLabel in buttons)
				bl.setFilters(newFilters);
		}
		
		public function CanvasLink(newCanvas:ExperimentCanvas)
		{
			super();
			canvas = newCanvas;
			
			rawSprite = new Sprite();
			addChild(rawSprite);
			
			button = new CanvasLinkLabel();
			buttons = new Vector.<CanvasBranchLabel>();
		}
		
		public function establishFromExisting(vl:VirtualLink):void
		{
			removeButtonsFromCanvas();
			link = vl;
			
			button.labelBackgroundColor = DARK_COLOR;
			button.labelColor = LIGHT_COLOR;
			button.canvasLink = this;
			if(link.type == VirtualLink.TYPE_LAN)
			{
				button.x = link.x;
				button.y = link.y;
			}
			if(canvas.contains(button))
				canvas.setElementIndex(button, 0);
			else
				canvas.addElementAt(button, 0);
			button.validateNow();
			button.Link = link;
			
			if(link.type == VirtualLink.TYPE_LAN)
			{
				buttons = new Vector.<CanvasBranchLabel>();
				var canvasNodes:CanvasNodeCollection = canvas.allNodes.getForVirtualNodes(link.interfaces.Nodes);
				for each(var node:CanvasNode in canvasNodes.collection)
				{
					var newBranchLabel:CanvasBranchLabel = new CanvasBranchLabel();
					newBranchLabel.labelBackgroundColor = DARK_COLOR;
					newBranchLabel.canvasLink = this;
					canvas.addElementAt(newBranchLabel, 0);
					newBranchLabel.validateNow();
					newBranchLabel.setTo(link, link.interfaces.getByHost(node.Node));
					
					buttons.push(newBranchLabel);
				}
			}
			
			
			canvas.validateNow();
			canvas.setElementIndex(this, 0);
			drawEstablished();
		}
		
		private var editable:Boolean = true;
		public function setEditable(isEditable:Boolean):void
		{
			editable = isEditable;
			button.editable = editable;
			for each(var g:CanvasBranchLabel in buttons)
				g.editable = editable;
		}
		
		private function removeButtonsFromCanvas():void
		{
			for each(var g:CanvasBranchLabel in buttons)
				canvas.removeElement(g);
		}
		
		public function removeFromCanvas():void
		{
			removeButtonsFromCanvas();
			canvas.removeElement(button);
			canvas.removeElement(this);
		}
		
		public function removeBranch(bl:CanvasBranchLabel):void
		{
			link.removeInterface(bl.iface);
			canvas.removeElement(bl);
			buttons.splice(buttons.indexOf(bl), 1);
			drawEstablished();
		}
		
		public function get MiddlePoint():Point
		{
			return button.MiddlePoint;
		}
		
		public function get MiddleX():Number
		{
			return button.MiddleX;
		}
		
		public function get MiddleY():Number
		{
			return button.MiddleY;
		}
		
		public function get ContainerWidth():Number
		{
			return button.ContainerWidth;
		}
		
		public function get ContainerHeight():Number
		{
			return button.ContainerHeight;
		}
		
		public function setLocation(newX:Number = -1, newY:Number = -1):void
		{
			button.setLocation(newX, newY);
		}
		
		public function drawEstablished():void
		{
			rawSprite.graphics.clear();
			rawSprite.graphics.lineStyle(
				2,
				DARK_COLOR,
				1.0,
				true,
				LineScaleMode.NORMAL,
				CapsStyle.ROUND
			);
			
			var canvasNodes:CanvasNodeCollection = canvas.allNodes.getForVirtualNodes(link.interfaces.Nodes);
			
			if(link.type == VirtualLink.TYPE_LAN)
			{
				button.x = link.x;
				button.y = link.y;
				for each(var cnode:CanvasNode in canvasNodes.collection)
				{
					rawSprite.graphics.moveTo(button.MiddleX, button.MiddleY);
					rawSprite.graphics.lineTo(cnode.MiddleX, cnode.MiddleY);
					
					var buttonGroup:CanvasBranchLabel = getButtonFor(cnode);
					buttonGroup.setTo(link, link.interfaces.getByHost(cnode.Node));
					buttonGroup.x = (button.MiddleX + cnode.MiddleX)/2 - (buttonGroup.ContainerWidth/2 + 1);
					buttonGroup.y = (button.MiddleY + cnode.MiddleY)/2 - (buttonGroup.ContainerHeight/2);
				}
			}
			else
			{
				button.Link = link;
				button.x = (canvasNodes.collection[0].MiddleX + canvasNodes.collection[1].MiddleX)/2 - (button.ContainerWidth/2 + 1);
				button.y = (canvasNodes.collection[0].MiddleY + canvasNodes.collection[1].MiddleY)/2 - (button.ContainerHeight/2);
				
				rawSprite.graphics.moveTo(canvasNodes.collection[0].MiddleX, canvasNodes.collection[0].MiddleY);
				rawSprite.graphics.lineTo(canvasNodes.collection[1].MiddleX, canvasNodes.collection[1].MiddleY);
			}
		}
	}
}