// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <string.h>
#include <print.h>
#include "xassert.h"
#include "xtcp_client.h"
#include "tcp_xscope_handler.h"
#include "tcp_handler.h"
#include "udp_handler.h"

#define TCP_XSCOPE_PORT	1200

typedef enum {
  XSCOPE_CMD_LISTEN  = 0,
  XSCOPE_CMD_CONNECT = 1,
  XSCOPE_CMD_SEND    = 2,
  XSCOPE_CMD_CLOSE   = 3,
  XSCOPE_CMD_CTRLR_SEND = 4,
} xscope_cmd_t;

typedef enum {
  PROTO_TCP = 0,
  PROTO_UDP = 1,
} xscope_proto_t;

typedef struct xscope_protocol {
  xscope_cmd_t cmd_type;
  unsigned sub_cmd_type;
  unsigned port_no; //for device as server conn, this will be device listen port; for device as client, this will be host connection port
  xscope_proto_t protocol;
} xscope_protocol;


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
  int len = 0;
  /* What to send? */
  fail("unimplemented");
  //xtcp_send(c_xtcp, data, len);
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
#define CONTROLLER_IP	{169, 254, 196, 179}
#if !defined(CONTROLLER_IP)
#warning No define of form CONTROLLER_IP
#error Rebuild the application with this define assigned to the host controller ip
#endif

    xtcp_ipaddr_t ipaddr = CONTROLLER_IP;
    /*ipaddr[0] = atoi(xscope_data.ip_addr_1);
    ipaddr[1] = atoi(xscope_data.ip_addr_2);
    ipaddr[2] = atoi(xscope_data.ip_addr_3);
    ipaddr[3] = atoi(xscope_data.ip_addr_4);*/

    switch (xscope_data.cmd_type) {
      case XSCOPE_CMD_LISTEN: //listen; for server type conn
        xtcp_listen(c_xtcp, xscope_data.port_no, xscope_data.protocol);
        printstr("Listening on port: ");
        printintln(xscope_data.port_no);
      break;
      case XSCOPE_CMD_CONNECT: //connect; for client type conn
        xtcp_connect(c_xtcp, xscope_data.port_no, ipaddr, xscope_data.protocol);
        printstr("Connected to host on port: ");
        printintln(xscope_data.port_no);
      break;
      case XSCOPE_CMD_SEND: { //Send data
        int conn_id;
        xtcp_connection_t conn;
    	if (PROTO_TCP == xscope_data.protocol)
          conn_id = get_tcp_conn_id(ipaddr,  xscope_data.port_no);
    	else if (PROTO_UDP == xscope_data.protocol)
          conn_id = get_udp_conn_id(ipaddr,  xscope_data.port_no);

        if (conn_id) {
       	  conn.id = conn_id;
          xtcp_init_send(c_xtcp, &conn);
       	  printstr("Sending data on the connection: ");
       	  printintln(conn_id);
        }
      }
      break;
      case XSCOPE_CMD_CLOSE: { //Close command
        int conn_id;
        xtcp_connection_t conn;
        if (PROTO_TCP == xscope_data.protocol)
          conn_id = get_tcp_conn_id(ipaddr,  xscope_data.port_no);
        else if (PROTO_UDP == xscope_data.protocol)
          conn_id = get_udp_conn_id(ipaddr,  xscope_data.port_no);

    	if (conn_id) {
       	  conn.id = conn_id;
       	  xtcp_close(c_xtcp, &conn);
       	  printstr("Closing the connection: ");
       	  printintln(conn_id);
        }
      }
      break;
      case XSCOPE_CMD_CTRLR_SEND: //this is a controller send command; do nothing
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
  switch (conn->event) {
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
    switch (conn->event) {
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
