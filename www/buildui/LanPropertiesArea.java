public class LanPropertiesArea extends PropertiesArea
{
    public boolean iCare( Thingee t ) {
	return (t instanceof LanThingee);
    }

    public String getName() { return "Lan Properties"; }

    public LanPropertiesArea() 
    {
	super();
	addProperty("name", "name:","", true, false);
	addProperty("bandwidth", "bandwidth(Mb/s):", "100", false, false);
	addProperty("latency", "latency(ms):", "0", false, false);
	addProperty("loss", "loss rate(0.0 - 1.0):", "0.0", false, false);
    }
};
