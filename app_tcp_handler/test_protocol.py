import socket,sys
import struct

# This simple script sends a TCP packet to a specified port at the
# IP address given as the first argument to the script
# This is to test the simple TCP example XC program

#usage: python test_tcp_host_manager.py <device_ip> <host_ip>
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
port = 1200

print "Connecting.."
sock.connect((sys.argv[1], port))
print "Connected"

#  char cmd_type;
#  char sub_cmd_type;
#  char port_no[4]; //for device as server conn, this will be device listen port; for device as client, this will be host connection port
#  char protocol; //0 - tcp; 1 - udp
#  char ip_addr_1[3];
#  char ip_addr_2[3];
#  char ip_addr_3[3];
#  char ip_addr_4[3];
data = (0, 0, 1234, 0)
format = struct.Struct('I I I I')
final_data = format.pack(*data)


print "Sending data: " 
print data
sock.sendall(final_data)

print "Closing..."
sock.close()
print "Closed"
