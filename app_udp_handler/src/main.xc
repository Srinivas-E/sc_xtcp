// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <platform.h>
#include "print.h"
#include "xtcp.h"
#include "ethernet_board_support.h"

// These intializers are taken from the ethernet_board_support.h header for
// XMOS dev boards. If you are using a different board you will need to
// supply explicit port structure intializers for these values
ethernet_xtcp_ports_t xtcp_ports =
    {on ETHERNET_DEFAULT_TILE: OTP_PORTS_INITIALIZER,
     ETHERNET_DEFAULT_SMI_INIT,
     ETHERNET_DEFAULT_MII_INIT_lite,
     ETHERNET_DEFAULT_RESET_INTERFACE_INIT};

// IP Config - change this to suit your network.  Leave with all
// 0 values to use DHCP/AutoIP
xtcp_ipconfig_t ipconfig = {
		{ 169, 254, 196, 178 }, // ip address (eg 192,168,0,2)
		{ 255, 255, 255, 0 }, // netmask (eg 255,255,255,0)
		//{ 0, 0, 0, 0 },
		//{ 0, 0, 0, 0 },
		{ 0, 0, 0, 0 } // gateway (eg 192,168,0,1)
};

#define RX_BUFFER_SIZE 300
#define INCOMING_PORT 15533
#define MAX_CONNECTIONS	4

/** Simple UDP reflection thread.
 *
 * This thread does the following:
 *
 *   - Reponds to incoming packets on port INCOMING_PORT and
 *     sends a packet with the same content back to the sender.
 *
 */
void udp_reflect(chanend c_xtcp)
{
  xtcp_connection_t conn;  // A temporary variable to hold
                           // connections associated with an event
  xtcp_connection_t responding_connection; // The connection to the remote end
                                           // we are responding to
  int send_flag = 0;  // This flag is set when the thread is in the
                      // middle of sending a response packet

  // The buffers for incoming data, outgoing responses and outgoing broadcast
  // messages
  char rx_buffer[RX_BUFFER_SIZE];
  char tx_buffer[RX_BUFFER_SIZE];
  int response_len;  // The length of the response the thread is sending

  // Maintain track of two connections. Initially they are not initialized
  // (which can be represented by setting their ID to -1
  responding_connection.id = -1;

  // Instruct server to listen and create new connections on the incoming port
  xtcp_listen(c_xtcp, INCOMING_PORT, XTCP_PROTOCOL_UDP);

  while (1) {
    select {

    // Respond to an event from the tcp server
    case xtcp_event(c_xtcp, conn):
      switch (conn.event)
        {
        case XTCP_IFUP:
          break;
        case XTCP_IFDOWN:
          // Tidy up and close any connections we have open
          if (responding_connection.id != -1) {
            xtcp_close(c_xtcp, responding_connection);
            responding_connection.id = -1;
          }
          break;
        case XTCP_NEW_CONNECTION:
          // The tcp server is giving us a new connection.
          // It is a remote host connecting on the listening port
          printstr("New connection to listening port:");
          printintln(conn.local_port);
          if (responding_connection.id == -1) {
        	  responding_connection = conn;
          }
          else {
        	  printstr("Cannot handle new connection");
        	  xtcp_close(c_xtcp, conn);
          }
          break;
        case XTCP_RECV_DATA:
          // When we get a packet in:
          //
          //  - fill the tx buffer
          //  - initiate a send on that connection
          //
          response_len = xtcp_recv_count(c_xtcp, rx_buffer, RX_BUFFER_SIZE);
          printstr("Got data: ");
          printint(response_len);
          printstrln(" bytes");

          for (int i=0;i<response_len;i++)
            tx_buffer[i] = rx_buffer[i];

          if (!send_flag) {
            xtcp_init_send(c_xtcp, conn);
            send_flag = 1;
            printstrln("Responding");
          }
          else {
            // Cannot respond here since the send buffer is being used
          }
          break;
      case XTCP_REQUEST_DATA:
      case XTCP_RESEND_DATA:
        // The tcp server wants data, this may be for the responding connection
    	xtcp_send(c_xtcp, tx_buffer, response_len);
        break;
      case XTCP_SENT_DATA:
        xtcp_complete_send(c_xtcp);
        // When a reponse is sent, the connection is closed opening up
        // for another new connection on the listening port
        printstrln("Sent Response");
        xtcp_close(c_xtcp, conn);
        responding_connection.id = -1;
        send_flag = 0;
        break;
      case XTCP_TIMED_OUT:
      case XTCP_ABORTED:
      case XTCP_CLOSED:
        printstr("Closed connection:");
        printintln(conn.id);
        break;
      case XTCP_ALREADY_HANDLED:
          break;
      }
      break;
    }
  }
}

// Program entry point
int main(void) {
	chan xtcp[1];
	par
	{
		// The TCP/IP server thread
               on ETHERNET_DEFAULT_TILE: ethernet_xtcp_server(xtcp_ports,
                                                              ipconfig,
                                                              xtcp,
                                                              1);
                // The simple udp reflector thread
                on stdcore[0]: udp_reflect(xtcp[0]);

	}
	return 0;
}
