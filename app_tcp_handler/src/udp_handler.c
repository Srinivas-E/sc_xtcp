// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <string.h>
#include <print.h>
#include "xtcp_client.h"
#include "udp_handler.h"

#define RX_BUFFER_SIZE 300
#define UDP_INCOMING_PORT 501
//#define MAX_CONNECTIONS	4

// The connection to the remote end we are responding to
xtcp_connection_t responding_connection;

int send_flag;
// The length of the response the thread is sending
int response_len;
char tx_buffer[RX_BUFFER_SIZE];

void udpd_init(chanend c_xtcp)
{
  // Instruct server to listen and create new connections on the incoming port
  xtcp_listen(c_xtcp, UDP_INCOMING_PORT, XTCP_PROTOCOL_UDP);
  responding_connection.id = -1;
}


static void udp_recv(chanend c_xtcp, xtcp_connection_t *conn)
{
	char rx_buffer[RX_BUFFER_SIZE];
    // When we get a packet in:
    //  - fill the tx buffer
    //  - initiate a send on that connection
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
}

/** Simple UDP event handler
 *
 * This thread does the following:
 *
 *   - Reponds to incoming packets on port UDP_INCOMING_PORT and
 *     sends a packet with the same content back to the sender.
 *
 */
void xtcp_handle_udp_event(chanend c_xtcp, xtcp_connection_t *conn)
{
  // We have received an event from the XTCP stack, so respond appropriately

  //printintln(conn->event);
  switch (conn->event)
    {
    case XTCP_IFUP:
      /* This is already handled in the tcp event handler */
      return;
    case XTCP_IFDOWN: {
        // Tidy up and close any connections we have open
        if (responding_connection.id != -1) {
          xtcp_close(c_xtcp, &responding_connection);
          responding_connection.id = -1;
        }
      }
      return;
    case XTCP_ALREADY_HANDLED:
      return;
    default:
      break;
    }

  // Check if the connection is an client app connection
  if (conn->local_port == UDP_INCOMING_PORT) {
    switch (conn->event)
      {
      case XTCP_NEW_CONNECTION:
        // The tcp server is giving us a new connection.
    	// It is a remote host connecting on the listening port
    	printstr("New connection to listening port:");
    	printintln(conn->local_port);
    	if (responding_connection.id == -1) {
    	  responding_connection = *conn;
    	}
    	else {
    	  printstr("Cannot handle new connection");
    	  xtcp_close(c_xtcp, conn);
    	}
        break;
      case XTCP_RECV_DATA:
        udp_recv(c_xtcp, conn);
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
        printintln(conn->id);
        break;
      default:
        // Ignore anything else
        break;
      }
    conn->event = XTCP_ALREADY_HANDLED;
  }
  ////
  return;
}

