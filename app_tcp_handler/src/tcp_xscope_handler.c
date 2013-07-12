// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <string.h>
#include <print.h>
#include "xtcp_client.h"
#include "tcp_xscope_handler.h"
#include "tcp_handler.h"

#define TCP_XSCOPE_PORT	1200

xscope_protocol xscope_data;
unsigned conn_active;

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

static void process_xscope_data(chanend c_xtcp, xscope_protocol xscope_data)
{
	/* Custom protocol definition
	 * Start with cmd_type, send end_token as 0 as last
	 * Listen:    0-dc-inport-proto-dc
	 * Connect:   1-dc-out_port-proto-host_ipconfig
	 * Send:      2-1-local_port-dc-remote_addr
	 * Close:     2-2-local_port-dc-remote_addr
	 */
	xtcp_ipaddr_t ipaddr = {169, 254, 196, 175};
	/*ipaddr[0] = atoi(xscope_data.ip_addr_1);
	ipaddr[1] = atoi(xscope_data.ip_addr_2);
	ipaddr[2] = atoi(xscope_data.ip_addr_3);
	ipaddr[3] = atoi(xscope_data.ip_addr_4);*/

    switch (xscope_data.cmd_type) {
      case 0: //listen; for server type conn
    	xtcp_listen(c_xtcp, xscope_data.port_no, xscope_data.protocol);
      break;
      case 1: //connect; for client type conn
   	    xtcp_connect(c_xtcp, xscope_data.port_no, ipaddr, xscope_data.protocol);
      break;
      case 2: { //Send data
    	int conn_id;
    	xtcp_connection_t conn;
        conn_id = get_conn_id(ipaddr,  xscope_data.port_no);
        if (conn_id) {
       	  conn.id = conn_id;
          xtcp_init_send(c_xtcp, &conn);
        }
      }
      break;
      case 3: { //Close command
    	int conn_id;
    	xtcp_connection_t conn;
        conn_id = get_conn_id(ipaddr, xscope_data.port_no);
        if (conn_id) {
       	  conn.id = conn_id;
       	  xtcp_close(c_xtcp, &conn);
        }
      }
      break;
      default:
    	printstrln("unknown command received");
      break;
    }
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
    	  process_xscope_data(c_xtcp, xscope_data);
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
