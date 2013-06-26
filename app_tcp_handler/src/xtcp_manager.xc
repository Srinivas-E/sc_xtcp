// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <xs1.h>
#include <print.h>
#include "xtcp_client.h"
#include "tcp_handler.h"
#include "udp_handler.h"

// The main tcp manager thread
void xtcp_manager(chanend c_xtcp)
{
  xtcp_connection_t conn;
  // Initiate the TCP connection states
  tcpd_init(c_xtcp);
  udpd_init(c_xtcp);

  // Loop forever processing TCP events
  while(1)
    {
      select
        {
        case xtcp_event(c_xtcp, conn):
		  xtcp_handle_tcp_event(c_xtcp, conn);
          xtcp_handle_udp_event(c_xtcp, conn);
          break;
        }
    }
}

