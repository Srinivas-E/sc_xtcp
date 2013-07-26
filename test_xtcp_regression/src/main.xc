// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <platform.h>
#include <xscope.h>
#include "xtcp.h"
#include "ethernet_board_support.h"
#include "xtcp_manager.h"
#include "producer_consumer.h"

// These intializers are taken from the ethernet_board_support.h header for
// XMOS dev boards. If you are using a different board you will need to
// supply explicit port structure intializers for these values
ethernet_xtcp_ports_t xtcp_ports =
    {on ETHERNET_DEFAULT_TILE: OTP_PORTS_INITIALIZER,
     ETHERNET_DEFAULT_SMI_INIT,
     ETHERNET_DEFAULT_MII_INIT_lite,
     ETHERNET_DEFAULT_RESET_INTERFACE_INIT};

#define STATIC_IP {169,254,196,178}

xtcp_ipconfig_t ipconfig =
{
#ifdef STATIC_IP
   STATIC_IP,
   {  255, 255, 255, 0},
   {  0, 0, 0, 0}
#else
   { 0, 0, 0, 0 },
   { 0, 0, 0, 0 },
   { 0, 0, 0, 0 }
#endif
};


void xscope_user_init(void) {
    xscope_register(0, 0, "", 0, "");
    xscope_config_io(XSCOPE_IO_BASIC);
}

// Program entry point
int main(void) {
    chan c_xtcp[1];
    chan c0, c1, c2, c3;
    chan c4, c5, c6, c7;
    chan c8, c9, c10, c11;

    par
    {
        // The main ethernet/tcp server
    	on ETHERNET_DEFAULT_TILE:
    	    ethernet_xtcp_server(xtcp_ports,
                                  ipconfig,
                                  c_xtcp,
                                  1);
        // The tcp manager core(s)
    	//on ETHERNET_DEFAULT_TILE: xtcp_manager(c_xtcp[0]);
    	on tile[0]: xtcp_manager(c_xtcp[0]);
    	/*on tile[0]: xtcp_manager(c_xtcp[1]);
          on tile[1]: xtcp_manager(c_xtcp[2]);
          on tile[1]: xtcp_manager(c_xtcp[3]);
          on tile[0]: xtcp_manager(c_xtcp[4]);
          on tile[1]: xtcp_manager(c_xtcp[5]);*/

    	on tile[0] : test_producer_consumer(c0, c1, c2, c3);
    	on tile[1] : test_producer_consumer(c0, c1, c2, c3);
    	on tile[0] : test_producer_consumer(c4, c5, c6, c7);
    	on tile[1] : test_producer_consumer(c4, c5, c6, c7);
    	on tile[0] : test_producer_consumer(c8, c9, c10, c11);
    	on tile[1] : test_producer_consumer(c8, c9, c10, c11);
    }
    return 0;
}
