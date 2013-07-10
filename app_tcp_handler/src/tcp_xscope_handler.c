// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <string.h>
#include <print.h>
#include "xtcp_client.h"
#include "tcp_xscope_handler.h"

#define TCP_XSCOPE_PORT	1200

unsigned conn_active;
extern xscope_protocol xscope_data;
extern unsigned rx_data;

// Initialize the connection states
void tcpd_xscope_init(chanend c_xtcp)
{
  // Listen on the app port
  xtcp_listen(c_xtcp, TCP_XSCOPE_PORT, XTCP_PROTOCOL_TCP);
}


/* This function does not intend to send any data to host over socket for now.
 * It uses a channel to send data when reverse xscope functionality is ready */
static void tcp_send(chanend c_xtcp, xtcp_connection_t *conn)
{
  char data[XTCP_CLIENT_BUF_SIZE];
  int len;
  /* What to send? */
  xtcp_send(c_xtcp, data, len);
}


// xscope socket data handler
void xtcp_handle_xscope_tcp_event(chanend c_xtcp, xtcp_connection_t *conn)
{
  // Ignore events that are not directly relevant to tcp handler
  //printintln(conn->event);
  switch (conn->event)
    {
    case XTCP_IFUP:
    case XTCP_IFDOWN:
      conn_active = 0;
      return;
    case XTCP_ALREADY_HANDLED:
      return;
    default:
      break;
    }

  // Check if the connection is an client app connection
  if (conn->local_port == TCP_XSCOPE_PORT) {
    switch (conn->event)
      {
      case XTCP_NEW_CONNECTION:
    	if (conn_active) {
    	  printstrln("a host connection is already active");
    	  xtcp_abort(c_xtcp, conn);
    	}
    	else
    	  conn_active = 1;
        break;
      case XTCP_RECV_DATA: {
    	  xtcp_recv(c_xtcp, (char *) &xscope_data);
    	  rx_data = 1;
        }
        break;
      case XTCP_SENT_DATA:
      case XTCP_REQUEST_DATA:
      case XTCP_RESEND_DATA:
        tcp_send(c_xtcp, conn);
        break;
      case XTCP_TIMED_OUT:
      case XTCP_ABORTED:
      case XTCP_CLOSED:
    	conn_active = 0;
        break;
      default:
        // Ignore anything else
        break;
      }
    conn->event = XTCP_ALREADY_HANDLED;
  }
  return;
}
