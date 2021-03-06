/*
 * Automatically generated by jrpcgen 1.0.5 on 1/8/05 2:03 PM
 * jrpcgen is part of the "Remote Tea" ONC/RPC package for Java
 * See http://acplt.org/ks/remotetea.html for details
 */
package net.emulab;
import org.acplt.oncrpc.*;
import java.io.IOException;

public class mtp_request_id implements XdrAble {
    public int request_id;
    public robot_position position;

    public mtp_request_id() {
    }

    public mtp_request_id(XdrDecodingStream xdr)
           throws OncRpcException, IOException {
        xdrDecode(xdr);
    }

    public void xdrEncode(XdrEncodingStream xdr)
           throws OncRpcException, IOException {
        xdr.xdrEncodeInt(request_id);
        position.xdrEncode(xdr);
    }

    public void xdrDecode(XdrDecodingStream xdr)
           throws OncRpcException, IOException {
        request_id = xdr.xdrDecodeInt();
        position = new robot_position(xdr);
    }

}
// End of mtp_request_id.java
