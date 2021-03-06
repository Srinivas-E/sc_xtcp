// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#ifndef TCP_HANDLER_H_
#define TCP_HANDLER_H_

#include "xtcp_client.h"

void tcpd_init(chanend tcp_svr);
void xtcp_handle_tcp_event(chanend tcp_svr, REFERENCE_PARAM(xtcp_connection_t, conn));
int get_tcp_conn_id (xtcp_ipaddr_t ipaddr, int port_no);

#endif /* TCP_HANDLER_H_ */
