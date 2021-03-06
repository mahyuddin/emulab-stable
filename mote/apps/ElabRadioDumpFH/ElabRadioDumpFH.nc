// $Id: ElabRadioDumpFH.nc,v 1.3 2005-06-27 22:11:57 johnsond Exp $

/*									tab:4
 * "Copyright (c) 2000-2003 The Regents of the University  of California.  
 * All rights reserved.
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without written agreement is
 * hereby granted, provided that the above copyright notice, the following
 * two paragraphs and the author appear in all copies of this software.
 * 
 * IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT
 * OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE UNIVERSITY OF
 * CALIFORNIA HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * 
 * THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
 * ON AN "AS IS" BASIS, AND THE UNIVERSITY OF CALIFORNIA HAS NO OBLIGATION TO
 * PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS."
 *
 * Copyright (c) 2002-2003 Intel Corporation
 * All rights reserved.
 *
 * This file is distributed under the terms in the attached INTEL-LICENSE     
 * file. If you do not find these files, copies can be found by writing to
 * Intel Research Berkeley, 2150 Shattuck Avenue, Suite 1300, Berkeley, CA, 
 * 94704.  Attention:  Intel License Inquiry.
 */
/* Author:	Phil Buonadonna
 * Revision:	$Id: ElabRadioDumpFH.nc,v 1.3 2005-06-27 22:11:57 johnsond Exp $
 */

/**
 * @author Phil Buonadonna
 */

configuration ElabRadioDumpFH {
}
implementation {
  components Main, ElabRadioDumpFHM, RadioCRCPacket as Comm,
      //UARTNoCRCPacket as UART,
      GenericComm as UART,
      LedsC,
      TimerC,
      CC1000ControlM;
  //FramerM, UART

  Main.StdControl -> ElabRadioDumpFHM;

    ElabRadioDumpFHM.Timer -> TimerC.Timer[unique("Timer")];
    ElabRadioDumpFHM.TimerFH -> TimerC.Timer[unique("Timer")];

  //ElabRadioDumpFHM.UARTControl -> FramerM;
  //ElabRadioDumpFHM.UARTSend -> FramerM;
  //ElabRadioDumpFHM.UARTReceive -> FramerM;
  //ElabRadioDumpFHM.UARTTokenReceive -> FramerM;
  ElabRadioDumpFHM.UARTControl -> UART;
  //ElabRadioDumpFHM.UARTSend -> UART;
  //ElabRadioDumpFHM.UARTReceive -> UART;
  ElabRadioDumpFHM.UARTSend -> UART.SendMsg[4];
  ElabRadioDumpFHM.UARTReceive -> UART.ReceiveMsg[4];
  ElabRadioDumpFHM.RadioControl -> Comm;
  ElabRadioDumpFHM.RadioSend -> Comm;
  ElabRadioDumpFHM.RadioReceive -> Comm;

  ElabRadioDumpFHM.Leds -> LedsC;

    ElabRadioDumpFHM.CC1000Control -> CC1000ControlM;

  //FramerM.ByteControl -> UART;
  //FramerM.ByteComm -> UART;
}
