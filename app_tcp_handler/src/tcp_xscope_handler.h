// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#ifndef TCP_XSCOPE_HANDLER_H_
#define TCP_XSCOPE_HANDLER_H_

#include "xtcp_client.h"

typedef struct xscope_protocol {
  unsigned cmd_type;
  unsigned sub_cmd_type;
  unsigned port_no; //for device as server conn, this will be device listen port; for device as client, this will be host connection port
  unsigned protocol; //0 - tcp; 1 - udp
}xscope_protocol;

void tcpd_xscope_init(chanend tcp_svr);
/* This function handles data received from host socket exposed by xscope socket interface */
void xtcp_handle_xscope_tcp_event(chanend tcp_svr, REFERENCE_PARAM(xtcp_connection_t, conn));

#endif /* TCP_XSCOPE_HANDLER_H_ */
