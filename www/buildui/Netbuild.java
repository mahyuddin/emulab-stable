/******** 
 * TODO:
 *
 * fix netscape icon issue
 * better validate (incl. IPs)
 * scroll workarea
 * (?) scroll property area
 * X lanlink stuff.
 * X respect loss pct   
 * X validate user input
 * X auto button
 * X validate name (e.g. no collisions)
 *
 */

import java.awt.*;
import java.awt.event.*;
import java.io.*;
import java.util.*;
import java.lang.*;
import java.net.*;
//import netscape.javascript.*;
//import java.io.*;

public class Netbuild extends java.applet.Applet 
    implements MouseListener, MouseMotionListener, ActionListener,
	       KeyListener
{
    private WorkArea workArea;
    private Palette  palette;

    private Panel propertiesPanel;

    private PropertiesArea linkPropertiesArea;
    private PropertiesArea lanPropertiesArea;
    private PropertiesArea nodePropertiesArea;
    private PropertiesArea iFacePropertiesArea;
    private PropertiesArea lanLinkPropertiesArea;

    private boolean mouseDown;
    private boolean clickedOnSomething;
    private boolean allowMove;
    private boolean dragStarted;
    private boolean shiftWasDown;
    private boolean selFromPalette;
    private int lastDragX, lastDragY;
    private int downX, downY;

    private static Netbuild me;

    private static Color cornflowerBlue;
    private static Color lightBlue;
    private static Color darkBlue;

    private String status;

    private int appWidth, appHeight;

    private int propAreaWidth;
    private int paletteWidth; 
    private int workAreaWidth;

    private int workAreaX;
    private int propAreaX;

    //    private Linko exportButton;
    private FlatButton exportButton;
    private FlatButton copyButton;
    private boolean copyButtonActive;

    static {
	cornflowerBlue  = new Color( 0.95f, 0.95f, 1.0f );
	lightBlue = new Color( 0.9f, 0.9f, 1.0f );
	darkBlue  = new Color( 0.3f, 0.3f, 0.5f );
    }

    // returns true if anything was added.
    private boolean doittoit( boolean needed, PropertiesArea which, boolean forceExpand ) {
	if (needed) {
	    if (which.isStarted()) {
		//		System.out.println("Refreshing");
		which.refresh();
		//		System.out.println("Done.");
	    } else {
		//System.out.println("Vising");
		which.setVisible(false);
		//System.out.println("v1");
		propertiesPanel.add( which );
		//System.out.println("v2");
		which.start();
		//System.out.println("v3");
		if (forceExpand) { 
		    which.showProperties(); 
		} else {
		    which.hideProperties();
		}
		//System.out.println("v4");
		which.setVisible(true);
		//System.out.println("Done.");
		return true;
	    }
	} else {
	    //System.out.println("Leaving alone.");
	    if (which.isStarted()) {
		//System.out.println("Stopping");
		which.stop();
		propertiesPanel.remove( which );
	    }
	    //System.out.println("Done.");
	}
	return false;
    }

    private void precachePropertiesAreas() {
	// this hack makes it so 
	// the widget creating goes on at app startup,
	// not when the user places the first node (that is very annoying)

	doittoit( true, nodePropertiesArea, false );
	doittoit( true, linkPropertiesArea, false );
	doittoit( true, lanPropertiesArea, false );
	doittoit( true, lanLinkPropertiesArea, false );
	doittoit( true, iFacePropertiesArea, false );
	propertiesPanel.doLayout();
	propertiesPanel.setVisible(false);
	propertiesPanel.repaint();
    }

    private void startAppropriatePropertiesArea() {
	int typeCount = 0;
	int selCount = 0;
	boolean needLanLink = false;
	boolean needLink    = false;
	boolean needLan     = false;
	boolean needIFace   = false;
	boolean needNode    = false;

	Enumeration en = Thingee.selectedElements();
		    
	while(en.hasMoreElements()) {
	    Thingee t = (Thingee)en.nextElement();
	    
	    if (t.propertyEditable) {
		if (t instanceof LanLinkThingee) { 
		    if (!needLanLink) typeCount++; 
		    needLanLink = true; 
		} else if (t instanceof LinkThingee) { 
		    if (!needLink) typeCount++; 
		    needLink = true;
		} else if (t instanceof LanThingee) { 
		    if (!needLan) typeCount++; 
		    needLan = true; 
		    selCount++;
		} else if (t instanceof IFaceThingee) { 
		    if (!needIFace) typeCount++; 
		    needIFace = true;
		} else if (t instanceof NodeThingee) { 
		    if (!needNode) typeCount++; 
		    needNode = true;
		    selCount++;
		}
	    }
	}

	boolean exp = typeCount <= 1;
	propertiesPanel.setVisible( false );
	boolean changes = false;
	changes |= doittoit( needNode, nodePropertiesArea, exp );
	changes |= doittoit( needLink, linkPropertiesArea, exp );
	changes |= doittoit( needLan,  lanPropertiesArea, exp );
	changes |= doittoit( needLanLink, lanLinkPropertiesArea, exp );
	changes |= doittoit( needIFace, iFacePropertiesArea, exp );

	if (selCount > 0) {
	    if (!copyButton.isVisible()) { 
		copyButton.setVisible( true );
		propertiesPanel.add( copyButton ); 
	    } else {
		// this is so it is always on the bottom.
		if (changes) {
		    // if a panel got added.. re-cycle to the bottom.
		    propertiesPanel.remove( copyButton );
		    propertiesPanel.add( copyButton );
		}
	    }
	} else {
	    if (copyButton.isVisible()) {
		propertiesPanel.remove( copyButton );
		copyButton.setVisible( false );
	    }
	}

	propertiesPanel.doLayout();
	propertiesPanel.setVisible( true );
    }

    private boolean isInWorkArea( int x, int y ) {
	return x > workAreaX && y > 0 &&
               x < workAreaX + workAreaWidth &&
	       y < appHeight;
    }

    public static void redrawAll() {
	me.repaint();
    }

    public static void setStatus( String newStatus ) {
	me.status = newStatus;
	//	g.drawString( status, workAreaX + 4, 474 );
	me.repaint( me.workAreaX + 4, 420, 640 - (me.workAreaX + 4), 60);
    }

    public static Image getImage( String name ) {
	try {
	    System.out.println( "Trying to load image" );
	    //System.out.println( me.getCodeBase() );
	    //System.out.println( name );
	    //return me.getImage( me.getCodeBase(), name );
	    
	    URL codeBase = me.getCodeBase();
	    URL url = new URL( codeBase, name );
	    System.out.println( url.toString() );
	    Image im = me.getImage( url );
	    if (im == null) { System.out.println( "Failed to load image." ); }
	    return im;
	} catch (Exception e) {
	    System.out.println("Error getting image.");
	    return null;
	}
	//return me.getImage( me.getCodeBase(), name );
    }

    public void keyTyped( KeyEvent e ) {}

    public void keyPressed( KeyEvent e ) {
	System.out.println("Woo.");
	if (e.getKeyCode() == KeyEvent.VK_C) {
	    prePaintSelChange();
	    workArea.copySelected();
	    paintSelChange();
	}
    }
    public void keyReleased( KeyEvent e ) {}
	
    public void mouseMoved( MouseEvent e ) {}

    public void mouseDragged( MouseEvent e ) {
	if (!mouseDown) { return; }
	Graphics g = getGraphics();
	g.setXORMode( Color.white );

	if (clickedOnSomething) {
	    if (allowMove) {
		if (dragStarted) {
		    if (palette.hitTrash( lastDragX + downX, lastDragY + downY )) {
			palette.funktasticizeTrash( g );
		    }
		    Enumeration en = Thingee.selectedElements();
		    
		    while(en.hasMoreElements()) {
			Thingee t = (Thingee)en.nextElement();
			if (t.moveable || t.trashable) {
			    if (selFromPalette) {
				g.drawRect( t.getX() + lastDragX - 16 , t.getY() + lastDragY - 16, 32, 32 );
			    } else{
				g.drawRect( t.getX() + lastDragX - 16 + workAreaX, 
					    t.getY() + lastDragY - 16, 
					    32, 32 );
			    }
			}
		    }
		}
		
		dragStarted = true;

		lastDragX = e.getX() - downX;
		lastDragY = e.getY() - downY;	

		if (palette.hitTrash( e.getX(), e.getY() )) {
		    palette.funktasticizeTrash( g );
		}		
		
		Enumeration en = Thingee.selectedElements();
		
		while(en.hasMoreElements()) {
		    Thingee t = (Thingee)en.nextElement();
		    if (t.moveable || t.trashable) {
			if (selFromPalette) {
			    g.drawRect( t.getX() + lastDragX - 16 , t.getY() + lastDragY - 16, 32, 32 );
			} else{
			    g.drawRect( t.getX() + lastDragX - 16 + workAreaX, 
					t.getY() + lastDragY - 16, 
					32, 32 );
			}
		    }
		}
	    }
	} else {
	    int leastX = downX;
	    int sizeX  = lastDragX;
	    int leastY = downY;
	    int sizeY  = lastDragY;
	    if (downX + lastDragX < leastX) { 
		leastX = downX + lastDragX; 
		sizeX  = -lastDragX;
	    }
	    if (downY + lastDragY < leastY) { 
		leastY = downY + lastDragY; 
		sizeY  = -lastDragY;
	    }
	    
	    if (dragStarted) {
		//g.drawRect( downX, downY, lastDragX, lastDragY );
		g.drawRect( leastX, leastY, sizeX, sizeY );
	    }
	    dragStarted = true;
	    lastDragX = e.getX() - downX;
	    lastDragY = e.getY() - downY;	

	    {
		int leastX2 = downX;
		int sizeX2  = lastDragX;
		int leastY2 = downY;
		int sizeY2  = lastDragY;
		if (downX + lastDragX < leastX2) { 
		    leastX2 = downX + lastDragX; 
		    sizeX2  = -lastDragX;
		}
		if (downY + lastDragY < leastY2) { 
		    leastY2 = downY + lastDragY; 
		    sizeY2  = -lastDragY;
		}

		g.drawRect( leastX2, leastY2, sizeX2, sizeY2 );		
		//g.drawRect( downX2, downY2, lastDragX2, lastDragY2 );
	    }
	}
	g.setPaintMode();
    }

    public int postIt( String s ) {
	int hash = s.hashCode();
	if (hash < 0) { hash = -hash; }
	if (hash == 0) { hash = 1; }
	try {	    
	    URL url;
	    URLConnection urlConn;
	    DataOutputStream    printout;
	    DataInputStream     input;
	    // URL of CGI-Bin script.
	    //url = new URL (getCodeBase().toString() + "env.tcgi");
	    url = new URL ( getParameter("exporturl") );
	    // URL connection channel.
	    urlConn = url.openConnection();
	    // Let the run-time system (RTS) know that we want input.
	    urlConn.setDoInput (true);
	    // Let the RTS know that we want to do output.
	    urlConn.setDoOutput (true);
	    // No caching, we want the real thing.
	    urlConn.setUseCaches (false);
	    // Specify the content type.
	    urlConn.setRequestProperty("Content-Type", 
				       "application/x-www-form-urlencoded");
	    // Send POST output.
	    printout = new DataOutputStream (urlConn.getOutputStream ());
	    String content =	    
		"nsdata=" + URLEncoder.encode ( s ) +
                "&nsref=" + String.valueOf(hash);
	    printout.writeBytes (content);
	    printout.flush ();
	    printout.close ();
	    // Get response data.
	    input = new DataInputStream (urlConn.getInputStream ());
	    String str;
	    while (null != ((str = input.readLine()))) {
		System.out.println (str);
	    }
	    input.close();
	    
	} catch (Exception ex) {
	    System.out.println("exception: " + ex.getMessage());
	    ex.printStackTrace();	       
	    return -1;
	}
	return hash;
    }


    // public void toCookie( String s ) {
    //   java.util.Calendar c = java.util.Calendar.getInstance();
    //   c.add(java.util.Calendar.MONTH, 1);
    //   String expires = "; expires=" + c.getTime().toString();

    //   String s1 = s + expires; 
    //   System.out.println(s1);
        
    //   JSObject myBrowser = JSObject.getWindow(this);
    //   JSObject myDocument =  (JSObject) myBrowser.getMember("document");
    
    //   myDocument.setMember("cookie", s1);
    //}

    public void actionPerformed( ActionEvent e ) {
	if (e.getSource() == exportButton) {
	    startAppropriatePropertiesArea(); // make sure strings are up'd
	    String ns = workArea.toNS();
	    System.out.println( ns );	
	    int refid = postIt( ns );	
	    //String url = getParameter("exporturl") + "?nsdata=" + 
	    //URLEncoder.encode( ns );
	    //toCookie( ns );
	    //String url = getParameter("exporturl") + "?nsdataincookie=1";
	    String url = getParameter("expcreateurl") + "?nsref=" + String.valueOf(refid);
	    System.out.println( url );
	    try {
		getAppletContext().showDocument( new URL( url ), "_blank" );
	    } catch (Exception ex) {
		System.out.println("exception: " + ex.getMessage());
		ex.printStackTrace();	       
	    }
	} else if (e.getSource() == copyButton) {
	    prePaintSelChange();
	    workArea.copySelected();
	    paintSelChange();
	    startAppropriatePropertiesArea();
	}
    }

    public void mousePressed( MouseEvent e ) {
	mouseDown = true;
	int x = e.getX();
	int y = e.getY();
	/*
	  if (x < 8 && y < 8) {
	
	    try {
	    File foo = new File( "out.txt" );
	    FileOutputStream fos = new FileOutputStream( foo );
	    FilterOutputStream foos = new FilterOutputStream( fos );
	    PrintWriter pw = new PrintWriter( foos );
	    pw.println( workArea.toNS() );
	    pw.flush();
	    } catch (Exception ex ) {
		System.out.println("exception: " + ex.getMessage());
		ex.printStackTrace();	       
		//System.out.println( workArea.toNS());

	    }
	}
*/

	shiftWasDown = e.isShiftDown();
	downX = x;
	downY = y;

	lastDragX = 0;
	lastDragY = 0;

	Thingee clickedOn;

        prePaintSelChange();

	if (isInWorkArea(x,y)) {
	    clickedOn = workArea.clicked( x - paletteWidth, y );
	    selFromPalette = false;
	} else { 
	    Thingee.deselectAll();
	    clickedOn = palette.clicked(x, y);
	    selFromPalette = true;
	}

	clickedOnSomething = (clickedOn != null);

	if (e.isControlDown()) {
	    allowMove = false;
	    if (clickedOnSomething) {
		Enumeration en = Thingee.selectedElements();
		
		while(en.hasMoreElements()) {
		    Thingee a = (Thingee)en.nextElement();
		    Thingee b = clickedOn;
		    
		    if (a != b &&
			a != null && b != null &&
			a.linkable && b.linkable) {
			if (a instanceof NodeThingee && b instanceof NodeThingee) {		
			    LinkThingee t = new LinkThingee(Thingee.genName("link"), a, b );
			    workArea.add( t );
			    IFaceThingee it = new IFaceThingee("", a, t );
			    workArea.add( it );
			    IFaceThingee it2 = new IFaceThingee("", b, t );
			    workArea.add( it2 );
			    paintThingee( t );
			    paintThingee( it );
			    paintThingee( it2 );
			} else if (a instanceof NodeThingee && b instanceof LanThingee) {
			    LinkThingee t = new LanLinkThingee("", a, b);
			    workArea.add( t );
			    IFaceThingee it = new IFaceThingee("", a, t );
			    workArea.add( it );
			    paintThingee( t );
			    paintThingee( it );
			} else if (b instanceof NodeThingee && a instanceof LanThingee) {
			    LinkThingee t = new LanLinkThingee("", a, b);
			    workArea.add( t );
			    IFaceThingee it = new IFaceThingee("", b, t );
			    workArea.add( it );
			    paintThingee( t );
			    paintThingee( it );
			} else if (a instanceof LanThingee && b instanceof LanThingee ) {
			    Netbuild.setStatus("!LAN to LAN connection not allowed.");
			} else {
			    
			}
		    }

		}
	    }
	} else {// if (e.controlDown())
	    allowMove = true;
	    if (clickedOn == null) {
		if (!e.isShiftDown()){
		    Thingee.deselectAll();
		}
	    } else if (clickedOn.isSelected()) {
		if (!e.isShiftDown()) {

		} else {
		    clickedOn.deselect();
		}
	    } else {
		if (!e.isShiftDown()) {
		    Thingee.deselectAll();
		}
		clickedOn.select();
	    }
	}

        paintSelChange();
	startAppropriatePropertiesArea();

	//repaint();

	dragStarted = false;
    }

    private void paintThingee( Thingee t ) {
	Rectangle r = t.getRectangle();
	
	// HACK!
	if (palette.has( t )) {
	    repaint( r.x, r.y, r.width, r.height );
	} else {
	    repaint( r.x + workAreaX, r.y, r.width, r.height );
	}
    } 

    private Dictionary wasSelected;
    
    private void prePaintSelChange() {
	wasSelected = new Hashtable();
	Enumeration en = Thingee.selectedElements();
	
	while(en.hasMoreElements()) {	   
	    Thingee t = (Thingee)en.nextElement();
	    wasSelected.put( t, new Integer(1));
	}
    }	

    private void paintSelChange() {
	Enumeration en = Thingee.selectedElements();
	
	while(en.hasMoreElements()) {
	    Thingee t = (Thingee)en.nextElement();

	    if (wasSelected.get(t) == null) {
		paintThingee(t);
		wasSelected.remove(t);
	    }
	}

	en = wasSelected.keys();

	while(en.hasMoreElements()) {
	    Thingee t = (Thingee)en.nextElement();
	    paintThingee(t);
	}
    }

    public void mouseReleased( MouseEvent e ) {
	if (!mouseDown) { return; }
	mouseDown = false;
	if (clickedOnSomething) {
	    if (dragStarted) {
		Graphics g = getGraphics();
		g.setXORMode( Color.white );

		if (palette.hitTrash( lastDragX + downX, lastDragY + downY )) {
		    palette.funktasticizeTrash( g );
		}
		
		{
		    Enumeration en = Thingee.selectedElements();
		    
		    while(en.hasMoreElements()) {
			Thingee t = (Thingee)en.nextElement();
			if (t.moveable || t.trashable) {
			    if (selFromPalette) {
				g.drawRect( t.getX() + lastDragX - 16 , t.getY() + lastDragY - 16, 32, 32 );
			    } else{
				g.drawRect( t.getX() + lastDragX - 16 + workAreaX, 
					    t.getY() + lastDragY - 16, 
					    32, 32 );
			    }
			}
		    }
		}
		
		g.setPaintMode();
		
		int x = e.getX();
		int y = e.getY();
		
		if (selFromPalette) {
		    // from palette..
		    if (x < paletteWidth) {
			// back to palette -- nothing happens.
		    } else {
			// into workarea. Create.
			prePaintSelChange();
			Thingee t;
			if (Thingee.selectedElements().nextElement() instanceof NodeThingee) {
			    t = new NodeThingee(Thingee.genName("node"));
			    Netbuild.setStatus("Node created.");
			} else {
			    t = new LanThingee(Thingee.genName("lan"));
			    Netbuild.setStatus("LAN created.");
			}
			t.move( x - workAreaX, y );
			workArea.add( t );
			Thingee.deselectAll();
			t.select();
			selFromPalette = false;
			startAppropriatePropertiesArea();
			//paintThingee(t);
			paintSelChange();
			exportButton.setEnabled( true );
			//repaint();
		    }
		} else {
		    // from workarea..
		    if (!isInWorkArea(x,y)) {
			// out of work area.. but to where?
			if (palette.hitTrash( x, y )) {
			    Enumeration en = Thingee.selectedElements();
			    
			    while(en.hasMoreElements()) {
				Thingee t = (Thingee)en.nextElement();
				if (t.trashable) {
				// into trash -- gone.
				    t.deselect();
				    workArea.remove(t);
				    Netbuild.setStatus("Selection trashed.");
				} else if (t instanceof IFaceThingee) {
				    t.deselect();
				}
			    }
			    repaint();
			    startAppropriatePropertiesArea();

			    if (workArea.getThingeeCount() < 1) {
				exportButton.setEnabled( false );
			    }
			} else if (palette.hitCopier( x, y )) {
			    	    prePaintSelChange();
				    workArea.copySelected();
				    paintSelChange();
			}
		    } else {
			Enumeration en = Thingee.selectedElements();
			
			while(en.hasMoreElements()) {
			    Thingee t = (Thingee)en.nextElement();
			    
			    if (t.moveable) {
				t.move( t.getX() + lastDragX, t.getY() + lastDragY );
			    }
			    repaint();
			}
		    }
		}
	    }
	} else { // if clickedonsomething
	    // dragrect

	    if (lastDragX != 0 && lastDragY != 0) {
		prePaintSelChange();
	    }

	    Graphics g = getGraphics();
	    g.setXORMode( Color.white );

	    int leastX = downX;
	    int sizeX  = lastDragX;
	    int leastY = downY;
	    int sizeY  = lastDragY;
	    if (downX + lastDragX < leastX) { 
		leastX = downX + lastDragX; 
		sizeX  = -lastDragX;
	    }
	    if (downY + lastDragY < leastY) { 
		leastY = downY + lastDragY; 
		sizeY  = -lastDragY;
	    }
	    
	    if (dragStarted) {
		//		    g.drawRect( downX, downY, lastDragX, lastDragY );
		g.drawRect( leastX, leastY, sizeX, sizeY );
	    }
	    g.setPaintMode();
	    /*
	      workArea.selectRectangle( new Rectangle( downX - workAreaX, 
	      downY - workAreaY, 
	      lastDragX, 
	      lastDragY), shiftWasDown );
	    */
	    if (lastDragX != 0 && lastDragY != 0) {
		workArea.selectRectangle( new Rectangle( leastX - workAreaX, 
							 leastY, 
							 sizeX, 
							 sizeY), shiftWasDown );
		
		paintSelChange();
		startAppropriatePropertiesArea();
	    }
	}
	dragStarted = false;
	lastDragX = 0;
	lastDragY = 0;
    }

    public void mouseEntered( MouseEvent e )  {}
    public void mouseExited(  MouseEvent e )  {}
    public void mouseClicked( MouseEvent e )  {}

    public String getAppletInfo() {
	return "Designs a network topology.";
    }

    //    public Netbuild() {
    //super();

    public void init() {
	status = "Netbuild v1.0 started.";
	me = this;
	mouseDown = false;

	setLayout( null );

	//setLayout( new FlowLayout( FlowLayout.RIGHT, 4, 4 ) );
	addMouseListener( this );
	addMouseMotionListener( this );
	addKeyListener( this );

	workArea = new WorkArea();
	palette  = new Palette();
	propertiesPanel = new Panel();

	nodePropertiesArea  = new NodePropertiesArea();
	linkPropertiesArea  = new LinkPropertiesArea();
	iFacePropertiesArea = new IFacePropertiesArea();
	lanPropertiesArea   = new LanPropertiesArea();
	lanLinkPropertiesArea = new LanLinkPropertiesArea();

	dragStarted = false;
	
	Dimension d = getSize();
	appWidth    = d.width - 1; //640;
	appHeight   = d.height - 1; //480;

        propAreaWidth = 160;
	paletteWidth  = 80;
	workAreaWidth = appWidth - propAreaWidth - paletteWidth;

	workAreaX = paletteWidth;
	propAreaX = paletteWidth + workAreaWidth;

	setBackground( darkBlue );
	propertiesPanel.setBackground( darkBlue );
	propertiesPanel.setVisible( true );

	exportButton = new FlatButton( "create experiment" );
	exportButton.addActionListener( this );

	copyButton = new FlatButton( "copy selection" );
	copyButton.addActionListener( this );

	add( propertiesPanel );

	propertiesPanel.setLocation( propAreaX + 8, 0 + 8 + 24 );
	propertiesPanel.setSize( propAreaWidth - 16, appHeight - 16 - 32 - 22);
	
	exportButton.setVisible( true );
	exportButton.setEnabled( false );
	add( exportButton );

	exportButton.setLocation( propAreaX + 8, appHeight - 24 - 2 - 2);
	exportButton.setSize( propAreaWidth - 16, 20 );

	copyButton.setVisible( false );
	copyButton.setSize( propAreaWidth - 16, 20);

	precachePropertiesAreas();
    }

    public void paint( Graphics g ) {
	g.setColor( lightBlue );
	g.fillRect( 0, 0, paletteWidth, appHeight );

	g.setColor( cornflowerBlue );
	g.fillRect( workAreaX, 0, workAreaX + workAreaWidth, appHeight );

	g.setColor( darkBlue );
	g.fillRect( propAreaX, 0, 
		    propAreaX + propAreaWidth, appHeight );
		   
	g.setColor( Color.black );
	g.drawRect( 0, 0, appWidth, appHeight );
	g.drawRect( 0, 0, paletteWidth, appHeight );
	g.drawRect( workAreaX, 0, workAreaWidth, appHeight );
	g.drawRect( propAreaX, 0, 
		    propAreaWidth, appHeight );

      
	if (status.compareTo("") != 0 && status.charAt(0) == '!') {
	    g.setColor( Color.red );
	}

	g.drawString( status, workAreaX + 4, appHeight - 6 );

	palette.paint( g );
      	//propertiesArea.paint( g );

	g.setColor( Color.black );
	g.fillRect( propAreaX + 8 - 3, appHeight - 24 - 2 - 8,
		    propAreaWidth - 16 + 6, 1 );

	g.setColor( Color.darkGray );
	g.fillRect( propAreaX + 8 - 3, appHeight - 24 - 2 - 7,
		    propAreaWidth - 16 + 6, 1 );

	g.translate( workAreaX, 0 );
	g.setClip( 1, 1, workAreaWidth - 1, appHeight - 1 );
	workArea.paint( g );
	g.translate( -workAreaX, 0 );
	g.setClip( 0, 0, appWidth, appHeight );
	super.paint(g);
    }
}






