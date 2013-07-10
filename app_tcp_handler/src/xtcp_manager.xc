// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <xs1.h>
#include <print.h>
#include <stdlib.h>
#include "xtcp_client.h"
#include "tcp_handler.h"
#include "udp_handler.h"
#include "tcp_xscope_handler.h"

xscope_protocol xscope_data;
unsigned rx_data;

static void process_xscope_data(chanend c_xtcp, xscope_protocol xscope_data)
{
	/* Custom protocol definition
	 * Start with cmd_type, send end_token as 0 as last
	 * Listen:    0-dc-inport-proto-dc
	 * Connect:   1-dc-out_port-proto-host_ipconfig
	 * Send:      2-1-local_port-dc-remote_addr
	 * Close:     2-2-local_port-dc-remote_addr
	 */
	xtcp_ipaddr_t ipaddr;
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
          xtcp_init_send(c_xtcp, conn);
        }
      }
      break;
      case 3: { //Close command
    	int conn_id;
    	xtcp_connection_t conn;
        conn_id = get_conn_id(ipaddr, xscope_data.port_no);
        if (conn_id) {
       	  conn.id = conn_id;
       	  xtcp_close(c_xtcp, conn);
        }
      }
      break;
      default:
    	printstrln("unknown command received");
      break;
    }
}

// The main tcp manager thread
void xtcp_manager(chanend c_xtcp)
{
  xtcp_connection_t conn;

  // Initiate the TCP connection states
  tcpd_xscope_init(c_xtcp);
  tcpd_init(c_xtcp);
  udpd_init(c_xtcp);

  // Loop forever processing TCP events
  while(1)
    {
      select
        {
        case xtcp_event(c_xtcp, conn):
		  xtcp_handle_xscope_tcp_event(c_xtcp, conn);
		  xtcp_handle_tcp_event(c_xtcp, conn);
          xtcp_handle_udp_event(c_xtcp, conn);
          break;
        default:
         if (rx_data) { //if there is any xscope data
           process_xscope_data(c_xtcp, xscope_data);
           rx_data = 0;
         }
         break;
        }
    }
}

