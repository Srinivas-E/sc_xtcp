#!/usr/bin/python
import socket,sys

# This simple script sends a TCP packet to a specified port at the
# IP address given as the first argument to the script
# This is to test the simple TCP example XC program

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
port = 500

print "Connecting.."
sock.connect((sys.argv[1], port))
print "Connected"

msg = "hello world"
print "Sending message: " + msg
sock.sendall(msg)
#for num in range(1, 10):
#  sock.sendall(msg)

rx_data = sock.recv(len(msg))
print "Received message: " + rx_data

print "Closing..."
sock.close()
print "Closed"

#server part

server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server_port = 501
server_address = (sys.argv[2], server_port)

server_sock.bind(server_address)
server_sock.listen(1)

while True:
  print "waiting for a client connection"
  connection, client_address = server_sock.accept()
  try:
    print >>sys.stderr, 'connection from', client_address

    while True:
      data = connection.recv(10)
      if data:
        print >>sys.stderr, 'received "%s"' % data
      else:
        print "no more data"
        break
  finally:
    connection.close()

