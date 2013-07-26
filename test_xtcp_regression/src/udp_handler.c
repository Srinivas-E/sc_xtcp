// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <string.h>
#include <print.h>
#include "xtcp_client.h"
#include "udp_handler.h"

#define UDP_MAX_CONNECTIONS	10
#define BUFFER_SIZE 300

typedef struct udp_app_state
{
  int active;        //< Whether this state structure is being used
                     //  for a connection
  int conn_id;       //< The connection id
  int port_no;       //< The port number based on connection type
  int dlen;          //< The length of the data to send
  char data[BUFFER_SIZE];

}udp_app_state;

udp_app_state udp_connection_state[UDP_MAX_CONNECTIONS];


void udpd_init(chanend c_xtcp)
{
  return; //do nothing
}

int get_udp_conn_id (xtcp_ipaddr_t ipaddr, int port_no)
{
  int i;
  ipaddr = 0; //Not used for now
  for (i = 0; i<UDP_MAX_CONNECTIONS; i++) {
    if ((udp_connection_state[i].port_no == port_no) &&
        (udp_connection_state[i].active))
      return udp_connection_state[i].conn_id;
  }
  return 0;
}

// Setup a new connection
static void udp_conn_init(chanend c_xtcp, xtcp_connection_t *conn)
{
  int i,j;

  // Try and find an empty connection slot
  for (i=0;i<UDP_MAX_CONNECTIONS;i++) {
    if (!udp_connection_state[i].active)
      break;
  }

  // If no free connection slots were found, abort the connection
  if ( i == UDP_MAX_CONNECTIONS ) {
    xtcp_close(c_xtcp, conn);
  }
  // Otherwise, assign the connection to a slot        //
  else {
    udp_connection_state[i].active = 1;
    udp_connection_state[i].conn_id = conn->id;
    udp_connection_state[i].dlen = 0;

    if (conn->connection_type == XTCP_SERVER_CONNECTION) {
      udp_connection_state[i].port_no = conn->local_port;
      memset(udp_connection_state[i].data, '\0', sizeof(udp_connection_state[i].data));
	}
	else { //if (conn->connection_type == XTCP_CLIENT_CONNECTION)
      udp_connection_state[i].port_no = conn->remote_port;
      //Fill the buffer with sample data to send
      for (j=0; j<BUFFER_SIZE;j++) {
        udp_connection_state[i].data[j] = 'a'+j%27;
      }
    }
  }
}

static int validate_port(xtcp_connection_t *conn)
{
  int i;

  for (i = 0; i<UDP_MAX_CONNECTIONS; i++) {
    if ( ((udp_connection_state[i].port_no == conn->local_port) && (conn->connection_type == XTCP_SERVER_CONNECTION)) ||
         ((udp_connection_state[i].port_no == conn->remote_port) && (conn->connection_type == XTCP_CLIENT_CONNECTION)) )
     return 1;
  }
  return 0;
}

static void udp_recv(chanend c_xtcp, xtcp_connection_t *conn)
{
  int i;
  for (i = 0; i<UDP_MAX_CONNECTIONS; i++) {
    if (udp_connection_state[i].conn_id == conn->id)
      break;
  }

  // If no free connection slots were found, abort the connection
  if ( i == UDP_MAX_CONNECTIONS ) {
    printstrln("Could not search a valid connection; error somewhere!!!");
    xtcp_close(c_xtcp, conn);
  }
  else {
    udp_connection_state[i].dlen = xtcp_recv_count(c_xtcp, udp_connection_state[i].data, BUFFER_SIZE);
    xtcp_init_send(c_xtcp, conn);
  }
}

static void udp_send(chanend c_xtcp, xtcp_connection_t *conn)
{
  int i;
  for (i = 0; i<UDP_MAX_CONNECTIONS; i++) {
    if (udp_connection_state[i].conn_id == conn->id)
      break;
  }

  // If no free connection slots were found, abort the connection
  if ( i == UDP_MAX_CONNECTIONS ) {
    printstrln("Could not search a valid connection; error somewhere!!!");
    xtcp_close(c_xtcp, conn);
  }
  else {
    xtcp_send(c_xtcp, udp_connection_state[i].data, udp_connection_state[i].dlen);
  }
}

static void udp_conn_close(chanend c_xtcp, xtcp_connection_t *conn)
{
  int i;
  for (i = 0; i<UDP_MAX_CONNECTIONS; i++) {
    if (udp_connection_state[i].conn_id == conn->id)
      break;
  }

  // If no free connection slots were found, abort the connection
  if ( i != UDP_MAX_CONNECTIONS ) {
    xtcp_complete_send(c_xtcp);
    xtcp_close(c_xtcp, conn);
  }
}

// Free a connection slot, for a finished connection
static void udp_conn_free(xtcp_connection_t *conn)
{
  int i;
  for ( i = 0; i<UDP_MAX_CONNECTIONS; i++ ) {
    if (udp_connection_state[i].conn_id == conn->id)
      udp_connection_state[i].active = 0;
  }
}

void xtcp_handle_udp_event(chanend c_xtcp, xtcp_connection_t *conn)
{
  switch (conn->event) {
    case XTCP_IFUP:
      /* This is already handled in the tcp event handler */
      return;
    case XTCP_IFDOWN:
   	  udp_conn_free(conn);
      return;
    case XTCP_ALREADY_HANDLED:
      return;
    default:
      break;
    }

  // Check if the connection is an client app connection
  if ( (XTCP_PROTOCOL_UDP == conn->protocol) &&
     ( (XTCP_NEW_CONNECTION == conn->event) || (validate_port(conn))) ) {
    switch (conn->event)
      {
      case XTCP_NEW_CONNECTION:
        udp_conn_init(c_xtcp, conn);
        break;
      case XTCP_RECV_DATA:
        udp_recv(c_xtcp, conn);
        break;
      case XTCP_REQUEST_DATA:
      case XTCP_RESEND_DATA:
        udp_send(c_xtcp, conn);
        break;
      case XTCP_SENT_DATA:
        /* The connection is immediately closed after sending the socket data */
        udp_conn_close(c_xtcp, conn);
        break;
      case XTCP_TIMED_OUT:
      case XTCP_ABORTED:
      case XTCP_CLOSED:
        udp_conn_free(conn);
        break;
      default:
        // Ignore anything else
        break;
      }
    conn->event = XTCP_ALREADY_HANDLED;
  }
  return;
}

