// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <string.h>
#include <print.h>
#include "xtcp_client.h"
#include "tcp_handler.h"

// Maximum number of concurrent connections
#define MAX_NUM_CONNECTIONS 10
// Buffer to hold the connection specific data
#define DATA_BUFFER_LEN	100

// Structure to hold TCP Connection state
typedef struct tcpd_state_t {
  int active;      //< Whether this state structure is being used
                   //  for a connection
  int conn_id;     //< The connection id
  int port_no;     //< The port number based on connection type
  char *dptr;      //< Pointer to the remaining data to send
  char data[DATA_BUFFER_LEN];
  int dlen;        //< The length of remaining data to send
  char *prev_dptr; //< Pointer to the previously sent item of data
} tcpd_state_t;

tcpd_state_t connection_states[MAX_NUM_CONNECTIONS];

// Initialize the connection states
void tcpd_init(chanend c_xtcp)
{
  int i;
  for ( i = 0; i < MAX_NUM_CONNECTIONS; i++ )  {
    connection_states[i].active = 0;
    connection_states[i].dptr = NULL;
  }
}

int get_conn_id (xtcp_ipaddr_t ipaddr, int port_no)
{
  int i;
  ipaddr = 0; //Not used for now
  for (i = 0; i<MAX_NUM_CONNECTIONS; i++) {
	if (connection_states[i].port_no == port_no)
	  return connection_states[i].conn_id;
  }
  return 0;
}

static int validate_port(xtcp_connection_t *conn)
{
  int i;

  for (i = 0;i<MAX_NUM_CONNECTIONS;i++) {
	  if ( ((connection_states[i].port_no == conn->local_port) && (conn->connection_type == XTCP_SERVER_CONNECTION)) ||
	       ((connection_states[i].port_no == conn->remote_port) && (conn->connection_type == XTCP_CLIENT_CONNECTION)) )
		return 1;
	  }
  return 0;
}

// Store the data received from a TCP request
static void parse_tcp_request(tcpd_state_t *conn_state, char *data, int len)
{
  int i;

  if (conn_state->dlen + len >= DATA_BUFFER_LEN) {
	//printstrln("Holding data is larger than buffer it can store");
	len = DATA_BUFFER_LEN - conn_state->dlen;
  }

  // Buffer the received data
  for (i=0;i<len;i++) {
    conn_state->data[i+conn_state->dlen] = *(data+i);
  }

  if (conn_state->dlen == 0)
    conn_state->dptr = conn_state->data;

  conn_state->dlen += len;
}

// Receive a TCP request
static void tcp_recv(chanend c_xtcp, xtcp_connection_t *conn)
{
  struct tcpd_state_t *conn_state = (struct tcpd_state_t *) conn->appstate;
  char data[XTCP_CLIENT_BUF_SIZE];
  int len;

  // Receive data from the TCP stack
  len = xtcp_recv(c_xtcp, data);

  if (conn_state == NULL)
	  return;

  // Otherwise we have data, so parse it
  parse_tcp_request(conn_state, &data[0], len);
}

// Send some data back for a TCP request
static void tcp_send(chanend c_xtcp, xtcp_connection_t *conn)
{
  struct tcpd_state_t *conn_state = (struct tcpd_state_t *) conn->appstate;
  int len = conn_state->dlen;

  // Check if we need to resend previous data
  if (conn->event == XTCP_RESEND_DATA) {
    xtcp_send(c_xtcp, conn_state->prev_dptr, (conn_state->dptr - conn_state->prev_dptr));
    return;
  }
  if (len > conn->mss)
    len = conn->mss;

  xtcp_send(c_xtcp, conn_state->dptr, len);

  conn_state->prev_dptr = conn_state->dptr;
  conn_state->dptr += len;
  conn_state->dlen -= len;

  if ((conn->event == XTCP_SENT_DATA) && (conn_state->dlen > 0)) {
	xtcp_init_send(c_xtcp, conn);
    return;
  }

}

// Setup a new connection
static void tcp_conn_init(chanend c_xtcp, xtcp_connection_t *conn)
{
  int i,j;

  // Try and find an empty connection slot
  for (i=0;i<MAX_NUM_CONNECTIONS;i++) {
	if (!connection_states[i].active)
	  break;
  }

  // If no free connection slots were found, abort the connection
  if ( i == MAX_NUM_CONNECTIONS ) {
	xtcp_abort(c_xtcp, conn);
  }
  // Otherwise, assign the connection to a slot        //
  else
    {
      connection_states[i].active = 1;
      connection_states[i].conn_id = conn->id;
      connection_states[i].dptr = connection_states[i].data;

      if (conn->connection_type == XTCP_SERVER_CONNECTION) {
    	connection_states[i].port_no = conn->local_port;
    	/* Clear up any previous or junk data */
        for (j=0; j<DATA_BUFFER_LEN;j++) {
      	  connection_states[i].data[j] = '\0';
        }
      }
      else { //if (conn->connection_type == XTCP_CLIENT_CONNECTION)
		connection_states[i].port_no = conn->remote_port;
        printstrln("Requested new conn received");
        //Fill the buffer with sample data to send
        for (j=0; j<DATA_BUFFER_LEN;j++) {
          connection_states[i].data[j] = 'a'+j%27;
        }
        connection_states[i].dlen = DATA_BUFFER_LEN-1;
      }

      xtcp_set_connection_appstate(
           c_xtcp,
           conn,
           (xtcp_appstate_t) &connection_states[i]);
    }
}

// Free a connection slot, for a finished connection
static void tcp_conn_free(xtcp_connection_t *conn)
{
  int i;
  for ( i = 0; i < MAX_NUM_CONNECTIONS; i++ ) {
	if (connection_states[i].conn_id == conn->id)
	  connection_states[i].active = 0;
  }
}

// TCP event handler
void xtcp_handle_tcp_event(chanend c_xtcp, xtcp_connection_t *conn)
{
  // We have received an event from the TCP stack, so respond
  // appropriately

  // Ignore events that are not directly relevant to tcp handler
  //printintln(conn->event);
  switch (conn->event)
    {
    case XTCP_IFUP: {
      xtcp_ipconfig_t ipconfig;
      xtcp_get_ipconfig(c_xtcp, &ipconfig);
      printstr("IP Address: ");
      printint(ipconfig.ipaddr[0]);printstr(".");
      printint(ipconfig.ipaddr[1]);printstr(".");
      printint(ipconfig.ipaddr[2]);printstr(".");
      printint(ipconfig.ipaddr[3]);printstr("\n");
    }
    return;
    case XTCP_IFDOWN:
      tcp_conn_free(conn);
      return;
    case XTCP_ALREADY_HANDLED:
      return;
    default:
      break;
    }

  // Check if the connection is an client app connection
  if ( (XTCP_PROTOCOL_TCP == conn->protocol) &&
     ( (XTCP_NEW_CONNECTION == conn->event) || (validate_port(conn))) ) {
    switch (conn->event)
      {
      case XTCP_NEW_CONNECTION:
        tcp_conn_init(c_xtcp, conn);
        break;
      case XTCP_RECV_DATA:
        tcp_recv(c_xtcp, conn);
        break;
      case XTCP_SENT_DATA:
      case XTCP_REQUEST_DATA:
      case XTCP_RESEND_DATA:
        tcp_send(c_xtcp, conn);
        break;
      case XTCP_TIMED_OUT:
      case XTCP_ABORTED:
      case XTCP_CLOSED:
        tcp_conn_free(conn);
        break;
      default:
        // Ignore anything else
        break;
      }
    conn->event = XTCP_ALREADY_HANDLED;
  }
  return;
}
