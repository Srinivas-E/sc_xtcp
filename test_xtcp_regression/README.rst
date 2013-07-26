XTCP regression tester
======================

:scope: Test application
:description: A regression test suite to test the sc_xtcp
:keywords: ethernet, tcp/ip, udp, regression

This test application serves as a regression test suite that supplements
a python based host controller framework in order to test the sc_xtcp 
component. 

The application handles connection set-up and tear down, simple data 
communication to and from the host, server and client type of connections
in tcp and udp mode.

Commands from the host are handled via reverse xscope command handling.