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
 
 package protogeni.display
{
	/**
	 * Predefined colors available for use.  Using one index into the colors
	 * basically give you three shades of the same color. It should be noted
	 * that in order to increase the number of colors they have been duplicated
	 * so that darks are also in lights and lights in darks so that you can
	 * have a dark on light and light and dark as two different schemes.
	 * 
	 * @author mstrum
	 * 
	 */
	public final class ColorUtil
	{
		public static const validDark:uint = 0x006600;
		public static const validLight:uint = 0x27C427;
		public static const invalidDark:uint = 0x990000;
		public static const invalidLight:uint = 0xF08080;
		public static const changingDark:uint = 0xCC6600;
		public static const changingLight:uint = 0xFFCC00;
		public static const unknownDark:uint = 0x2F4F4F;
		public static const unknownLight:uint = 0xEAEAEA;
		
		public static const colorsLight:Array = new Array(
			// light
			0xCCCCCC,	// grey
			0xF2AEAC,	// red
			0xD8E4AA,	// green
			0xB8D2EB,	// blue
			0xF2D1B0,	// orange
			0xD4B2D3,	// dark purple
			0xDDB8A9,	// dark red
			0xEBBFD9,	// light purple
			0xFFFCCF,	// NEW yellow
			0x49E9BD,	// NEW green
			0xFFD39B,	// NEW brown
			// dark
			0x010101,	// grey
			0xED2D2E,	// red
			0x008C47,	// green
			0x1859A9,	// blue
			0xF37D22,	// orange
			0x662C91,	// dark purple
			0xA11D20,	// dark red
			0xB33893,	// light purple
			0xCDAD00,	// NEW yellow
			0x388E8E,	// NEW green
			0x5C4033);	// NEW brown
		public static const colorsMedium:Array = new Array(
			0x727272,	// grey
			0xF1595F,	// red
			0x79C36A,	// green
			0x599AD3,	// blue
			0xF9A65A,	// orange
			0x9E66AB,	// dark purple
			0xCD7058,	// dark red
			0xD77FB3,	// light purple
			0xFFEC8B,	// NEW yellow
			0x45C3B8,	// NEW green
			0xAA6600,	// NEW brown
			0x727272,	// grey
			0xF1595F,	// red
			0x79C36A,	// green
			0x599AD3,	// blue
			0xF9A65A,	// orange
			0x9E66AB,	// dark purple
			0xCD7058,	// dark red
			0xD77FB3,	// light purple
			0xFFEC8B,	// NEW yellow
			0x45C3B8,	// NEW green
			0xAA6600);	// NEW brown
		public static const colorsDark:Array = new Array(
			0x010101,	// grey
			0xED2D2E,	// red
			0x008C47,	// green
			0x1859A9,	// blue
			0xF37D22,	// orange
			0x662C91,	// dark purple
			0xA11D20,	// dark red
			0xB33893,	// light purple
			0xCDAD00,	// NEW yellow
			0x388E8E,	// NEW green
			0x5C4033,	// NEW brown
			// light
			0xCCCCCC,	// grey
			0xF2AEAC,	// red
			0xD8E4AA,	// green
			0xB8D2EB,	// blue
			0xF2D1B0,	// orange
			0xD4B2D3,	// dark purple
			0xDDB8A9,	// dark red
			0xEBBFD9,	// light purple
			0xFFFCCF,	// NEW yellow
			0x49E9BD,	// NEW green
			0xFFD39B);	// NEW brown
		
		public static var nextColorIdx:int = 0;
		public static function getColorIdx():int
		{
			var value:int = nextColorIdx++;
			if(nextColorIdx == colorsMedium.length)
				nextColorIdx = 0;
			return value;
		}
	}
}