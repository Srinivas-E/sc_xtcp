// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#ifndef UDP_HANDLER_H_
#define UDP_HANDLER_H_

#include "xtcp_client.h"

void udpd_init(chanend tcp_svr);
void xtcp_handle_udp_event(chanend tcp_svr, REFERENCE_PARAM(xtcp_connection_t, conn));

#endif /* UDP_HANDLER_H_ */
