// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <xs1.h>
#include <xclib.h>
#include <print.h>
#include "tcp.h"
#include "tcpApplication.h"
#include "tx.h"
#include "checksum.h"
#include "ipv4.h"
#include "timer.h"

// RFC 793


#define APP_NOT_WAITING  0
#define APP_CLOSING      1
#define APP_READING      2
#define APP_WRITING      3
#define APP_ACCEPTING    4

#define TCPCONNECTIONS 10

#define BUFFERSIZE   1024

struct queue {
    int rd, wr, free, length;
    char buffer[BUFFERSIZE];
};

struct tcpConnection {
    unsigned short srcPortRev, dstPortRev;
    int srcIP, dstIP;
    short maxSegmentSize;
    char opened;
    char state;
    int outgoingSequenceNumber;     // Sequence number that we are transmitting (ours)
    int outgoingAckNumber;          // Ack number that we are transmitting (their sequence number)
    int incomingAckLast;            // Last ack that we received.
                                  // TODO: we should keep state associated with appWaiting
                                  // In particular whether app is waiting close/reading/writing.
    int appWaiting;               // This contains a streaming chanend if the app is waiting.
    int appStatus;                // THis contains one of APP_CLOSING, APP_READING, APP_ACCEPTING, APP_NOT_WAITING;
    int ackRequired;
    struct queue rx, tx;
};

struct tcpConnection tcpConnections[TCPCONNECTIONS] = {
    {0, 0x1700, 0, 0, 0, 0, 0},
};

#define FIN 0x01
#define SYN 0x02
#define RST 0x04
#define PSH 0x08
#define ACK 0x10
#define URG 0x20

#define CLOSED    0
#define LISTEN    2
#define SYNSENT   3
#define SYNRCVD   4
#define ESTAB     5
#define FINWAIT1  6
#define FINWAIT2  7
#define CLOSING   8
#define CLOSEWAIT 9
#define LASTACK  10
#define TIMEWAIT 11
#define TIMEWAIT0 12
#define TIMEWAIT1 13
#define TIMEWAIT2 14

void error(char msg[], int flags) {
    printstr(msg);
    printstr(" received flags ");
    printhexln(flags);
}


void pipOutgoingTCP(struct tcpConnection &conn, int length, int flags) {
    int totalLength = length + 20;
    int chkSum;
    int zero = 17;
    if (conn.ackRequired) {
        flags |= ACK;
    }
    txShort(zero+0, conn.dstPortRev);             // Store source port, already reversed
    txShort(zero+1, conn.srcPortRev);             // Store dst port, already reversed
    txInt(zero+2, byterev(conn.outgoingSequenceNumber)); // Sequence number, reversed
    if (flags & ACK) {
        txInt(zero+4, byterev(conn.outgoingAckNumber)); // Ack number, reversed
    } else {
        txInt(zero+4, 0); // Ack number, reversed
    }
    txShort(zero+6, flags<<8 | 0x50);             // Store dst port, already reversed
    txShort(zero+7, byterev(conn.rx.free > 255 ? 256 : conn.rx.free)>>16);   // Number of bytes free in window.
    txInt(zero+8, 0);                             // checksum, urgent pointer
    chkSum = onesChecksum(0x0006 + totalLength + onesAdd(myIP, conn.srcIP), (txbuf, unsigned short[]), 17, totalLength);
    txShort(zero+8, chkSum);                      // checksum.
    conn.ackRequired = 0;
    pipOutgoingIPv4(PIP_IPTYPE_TCP, conn.srcIP, totalLength);
//    printstr("Send ");
//    printhexln(conn.srcIP);
//    printhexln(totalLength);
}

static void appSendAcknowledge(struct tcpConnection & conn) {
#if PIP_TCP_ACK_CT != 3
#error "PIP_TCP_ACK_CT must be 3"
#endif
    asm("outct res[%0], 3" :: "r" (conn.appWaiting));
}

static void appSendClose(struct tcpConnection & conn) {
#if PIP_TCP_CLOSED_CT != 6
#error "PIP_TCP_CLOSED_CT must be 6"
#endif
    asm("outct res[%0], 6" :: "r" (conn.appWaiting));
    conn.appStatus = APP_NOT_WAITING;
}

static void goTimewait(struct tcpConnection & conn) {
    conn.state = TIMEWAIT;
    if (conn.appWaiting) {
        appSendAcknowledge(conn);
    }
}

void pipInitTCP() {
    pipSetTimeOut(PIP_TCP_TIMER_TIMEWAIT, 0, 10*1000*100, 0); // 10 ms clock
}

void pipTimeoutTCPTimewait() {
    for(int i = 0; i < TCPCONNECTIONS; i++) {
        switch(tcpConnections[i].state) {
        case TIMEWAIT:  tcpConnections[i].state = TIMEWAIT0; break;
        case TIMEWAIT0: tcpConnections[i].state = TIMEWAIT1; break;
        case TIMEWAIT1: tcpConnections[i].state = TIMEWAIT2; break;
        case TIMEWAIT2:
            tcpConnections[i].state = CLOSED;
            tcpConnections[i].opened = 0;
            if (tcpConnections[i].appWaiting) {
                appSendAcknowledge(tcpConnections[i]);
            }
            break;
        }
    }
    pipSetTimeOut(PIP_TCP_TIMER_TIMEWAIT, 0, 10*1000*100, 0); // 10 ms clock
}

static void bounceRST(int dstPortRev, int srcPortRev, int srcIP, int ackNumberRev, int sequenceNumberRev, int incorporateACK) {
    struct tcpConnection pseudoConnection;
    int flags;
    pseudoConnection.dstPortRev = dstPortRev;
    pseudoConnection.srcPortRev = srcPortRev;
    pseudoConnection.srcIP = srcIP;
    if (incorporateACK) {
        pseudoConnection.outgoingAckNumber = 0;
        pseudoConnection.outgoingSequenceNumber = byterev(ackNumberRev);
        flags = RST;
    } else {
        pseudoConnection.outgoingSequenceNumber = 0;
        pseudoConnection.outgoingAckNumber = byterev(sequenceNumberRev)+0;//todo LEN
        flags = ACK | RST;
    }
    pipOutgoingTCP(pseudoConnection, 0, flags);
}

static void copyDataForRead(struct tcpConnection &conn, streaming chanend app) {
    int bytesToSend, maxLength;
    soutct(app, PIP_TCP_ACK_CT);
    app :> maxLength;
    bytesToSend = BUFFERSIZE - conn.rx.free;
    if (bytesToSend > maxLength) {
        bytesToSend = maxLength;
    }
    conn.rx.free += bytesToSend;
    app <: bytesToSend;
    for(int i = 0; i < bytesToSend; i++) {
        app <: conn.rx.buffer[conn.rx.rd];
        conn.rx.rd = (conn.rx.rd + 1) & (BUFFERSIZE - 1);
    }
}

// TODO: reconcile with previous
static void copyDataForRead2(struct tcpConnection &conn, int app) {
    int bytesToSend, maxLength;
    asm("outct res[%0], 3" :: "r" (app));
    asm("in %0, res[%1]" : "=r" (maxLength) : "r" (app));
    bytesToSend = BUFFERSIZE - conn.rx.free;
    if (bytesToSend > maxLength) {
        bytesToSend = maxLength;
    }
    conn.rx.free += bytesToSend;
    asm("out res[%0], %1" :: "r" (app), "r" (bytesToSend));
    for(int i = 0; i < bytesToSend; i++) {
        asm("outt res[%0], %1" :: "r" (app), "r" (conn.rx.buffer[conn.rx.rd]));
        conn.rx.rd = (conn.rx.rd + 1) & (BUFFERSIZE - 1);
    }
}

static void storeIncomingData(struct tcpConnection &conn, unsigned short packet[],
                             int offset, int length) {
    int i;
    for(i = 0; i < length; i++) {
        if (conn.rx.free == 0) {
            break;
        }
        conn.rx.buffer[conn.rx.wr] = (packet, unsigned char[])[offset * 2 + i];
        conn.rx.wr = (conn.rx.wr + 1) & (BUFFERSIZE - 1);
        conn.rx.free--;
    }
    if (conn.appStatus == APP_READING && conn.rx.free != BUFFERSIZE) {
        copyDataForRead2(conn, conn.appWaiting);
        conn.appStatus = APP_NOT_WAITING;
    }
    conn.outgoingAckNumber += i;
}

static void copyDataFromWrite(struct tcpConnection &conn, streaming chanend app) {
    int bytesRequested;
    soutct(app, PIP_TCP_ACK_CT);
    app :> bytesRequested;
    if (bytesRequested > conn.tx.free) {
        bytesRequested = conn.tx.free;
    }
    conn.tx.free -= bytesRequested;
    conn.tx.length += bytesRequested;
    app <: bytesRequested;
    for(int i = 0; i < bytesRequested; i++) {
        app :> conn.tx.buffer[conn.tx.wr];
        conn.tx.wr = (conn.tx.wr + 1) & (BUFFERSIZE - 1);
    }
}

// TODO: Reconcile with previous
static void copyDataFromWrite2(struct tcpConnection &conn, unsigned app) {
    int bytesRequested;
    asm("outct res[%0],3" :: "r" (app));
    asm("in %0, res[%1]" : "=r" (bytesRequested) : "r" (app));
    if (bytesRequested > conn.tx.free) {
        bytesRequested = conn.tx.free;
    }
    conn.tx.free -= bytesRequested;
    conn.tx.length += bytesRequested;
    asm("out res[%0],%1" :: "r" (app), "r" (bytesRequested));
    for(int i = 0; i < bytesRequested; i++) {
        asm("int %0, res[%1]" : "=r" (conn.tx.buffer[conn.tx.wr]) : "r" (app));
        conn.tx.wr = (conn.tx.wr + 1) & (BUFFERSIZE - 1);
    }
}

static void loadOutgoingData(struct tcpConnection &conn) {
    int i;
    int length = 256;                    // Should be based on remote window.
    int offset = 27;
    if (length > conn.tx.length) { // Cannot send more data then we have
        length = conn.tx.length ;
    }
    conn.tx.length -= length;
    for(i = 0; i < length; i++) {
        txByte(offset * 2 + i, conn.tx.buffer[conn.tx.rd]);
        conn.tx.rd = (conn.tx.rd + 1) & (BUFFERSIZE - 1);
    }
    if (conn.appStatus == APP_WRITING && conn.tx.free != BUFFERSIZE) {
        copyDataForRead2(conn, conn.appWaiting);
        conn.appStatus = APP_NOT_WAITING;
    }
    pipOutgoingTCP(conn, i, PSH|ACK);
    conn.outgoingSequenceNumber += i;
}

int lextra = 0;
int lack = 0;

void pipIncomingTCP(unsigned short packet[], unsigned offset, unsigned srcIP, unsigned dstIP, unsigned totalLength) {
    int srcPortRev        = packet[offset+0];
    int dstPortRev        = packet[offset+1];
    int sequenceNumberRev = packet[offset+3]<<16 | packet[offset+2];
    int ackNumberRev      = packet[offset+5]<<16 | packet[offset+4];
    int dataOffset        = packet[offset+6] >> 4 & 0xF;
    int flags             = packet[offset+6] >> 8;
    int tcpOffset         = offset + dataOffset * 2;
    int window            = packet[offset+8];
    int length            = totalLength - dataOffset*4;

    int opened = -1;
    int openable = -1;

    for(int i = 0; i < TCPCONNECTIONS; i++) {
        if (dstPortRev == tcpConnections[i].dstPortRev) {
            if (tcpConnections[i].opened &&
                tcpConnections[i].srcPortRev == srcPortRev &&
                tcpConnections[i].srcIP      == srcIP &&
                tcpConnections[i].dstIP      == dstIP) { // Found the open stream.
                opened = i;
                break;
            }
            if (openable == -1 && !tcpConnections[i].opened) {
                openable = i;
            }
        }
    }
    if (opened == -1) {
        if (openable == -1) {               // Reject this connection; nobody listening.
            if (!(flags & RST)) {
                bounceRST(dstPortRev, srcPortRev, srcIP, ackNumberRev, sequenceNumberRev, !(flags & ACK));
            }
            return;
        }
        opened = openable;
        tcpConnections[opened].opened = 1;
        tcpConnections[opened].srcPortRev = srcPortRev;
        tcpConnections[opened].srcIP = srcIP;
        tcpConnections[opened].dstIP = dstIP;
        tcpConnections[opened].state = LISTEN;
        tcpConnections[opened].rx.rd = 0;
        tcpConnections[opened].rx.wr = 0;
        tcpConnections[opened].rx.free = BUFFERSIZE;
        tcpConnections[opened].rx.length = 0;
        tcpConnections[opened].tx.rd = 0;
        tcpConnections[opened].tx.wr = 0;
        tcpConnections[opened].tx.free = BUFFERSIZE;
        tcpConnections[opened].tx.length = 0;
    }

    switch(tcpConnections[opened].state) {
    case CLOSED:
        break;
    case LISTEN:
        if (flags & RST) {
            return;
        }
        if (flags & ACK) {
            bounceRST(dstPortRev, srcPortRev, srcIP, ackNumberRev, sequenceNumberRev, !(flags & ACK));
            return;
        }
        if (flags & SYN) {
            timer t;
            int t0;
            t :> t0;
            tcpConnections[opened].outgoingAckNumber = byterev(sequenceNumberRev) + 1;
            tcpConnections[opened].outgoingSequenceNumber = t0;
            tcpConnections[opened].incomingAckLast = t0;
            pipOutgoingTCP(tcpConnections[opened], 0, SYN|ACK);
            tcpConnections[opened].outgoingSequenceNumber++;
            tcpConnections[opened].state = SYNRCVD;
            return;
        }
        break;
    case SYNSENT:                    // Only relevant if we open a connection.
        error("SYNSENT", flags);
        break;
    case SYNRCVD:
        if (flags & ACK) {
            if(byterev(ackNumberRev) -  tcpConnections[opened].incomingAckLast != 1) {
                // TODO: just drop or send RST?
                return;
            }
            tcpConnections[opened].incomingAckLast++;
            tcpConnections[opened].state = ESTAB;
            if (tcpConnections[opened].appStatus == APP_ACCEPTING) {
                appSendAcknowledge(tcpConnections[opened]);
            }
            // Note or check sequence numbers?
            // TODO: must check sequence number and dump duplicate SYNRCVD.
            return;
        }
        error("SYNRCVD", flags);
        break;
    case ESTAB:
         // TODO: verify for duplicates and out of order packets.
        storeIncomingData(tcpConnections[opened], packet, tcpOffset, length);
        if (flags & FIN) {
            tcpConnections[opened].outgoingAckNumber++;
            pipOutgoingTCP(tcpConnections[opened], 0, ACK);
            tcpConnections[opened].state = CLOSEWAIT;
            if (tcpConnections[opened].appStatus == APP_WRITING ||
                tcpConnections[opened].appStatus == APP_READING) {
                appSendClose(tcpConnections[opened]);
            }
            return;
        }
        if (flags & ACK) {
            int newAckNumber = byterev(ackNumberRev);
            int extraBytes = newAckNumber - tcpConnections[opened].incomingAckLast;
            // TODO: check on ack and reject if not in range.
            lack = tcpConnections[opened].incomingAckLast;
            lextra = extraBytes;
            tcpConnections[opened].incomingAckLast = newAckNumber;
            tcpConnections[opened].tx.free += extraBytes;
            if (tcpConnections[opened].tx.free == extraBytes) {
                if (tcpConnections[opened].appStatus == APP_WRITING) {
                    copyDataFromWrite2(tcpConnections[opened], tcpConnections[opened].appWaiting);
                    tcpConnections[opened].appStatus = APP_NOT_WAITING;
                    loadOutgoingData(tcpConnections[opened]);
                }
            }

            // TODO
            if (length == 0) return;
        }
        if (tcpConnections[opened].ackRequired || 1) {
            pipOutgoingTCP(tcpConnections[opened], 0, ACK);
        } else {
            tcpConnections[opened].ackRequired = 1;
        }
        if (flags & ~FIN) {
            error("ESTAB", flags);
        }
        break;
    case FINWAIT1:
        if (flags & FIN) {
            tcpConnections[opened].outgoingAckNumber++;      // TODO
            pipOutgoingTCP(tcpConnections[opened], 0, ACK);
            tcpConnections[opened].state = CLOSING;
            return;
        }
        if (flags & ACK) {
            tcpConnections[opened].state = FINWAIT2;
            return;
        }
        error("FINWAIT1", flags);
        break;
    case FINWAIT2:
        if (flags & FIN) {
            tcpConnections[opened].outgoingAckNumber++;      // TODO
            pipOutgoingTCP(tcpConnections[opened], 0, ACK);
            goTimewait(tcpConnections[opened]);
            return;
        }
        error("FINWAIT2", flags);
        break;
    case CLOSING:
        if (flags & ACK) {
            tcpConnections[opened].state = TIMEWAIT;
            if (tcpConnections[opened].appStatus == APP_CLOSING) {
                appSendAcknowledge(tcpConnections[opened]);
            }
            return;
        }
        error("CLOSING", flags);
        break;
    case TIMEWAIT:
    case TIMEWAIT0:
    case TIMEWAIT1:
    case TIMEWAIT2:
        if (flags & FIN) {    // This is a result of a missed packet.
            tcpConnections[opened].outgoingAckNumber++;      // TODO
            pipOutgoingTCP(tcpConnections[opened], 0, ACK);
            tcpConnections[opened].state = TIMEWAIT;
            return;
        }
        error("TIMEWAIT", flags);
        break;
    case CLOSEWAIT:
        error("CLOSEWAIT", flags);
        break;
    case LASTACK:
        if (flags & ACK) {
            tcpConnections[opened].state  = CLOSED;
            tcpConnections[opened].opened = 0;
            if (tcpConnections[opened].appStatus == APP_CLOSING) {
                appSendAcknowledge(tcpConnections[opened]);
            }
            return;
        }
        error("CLOSING", flags);
        break;
    }
}

static void setAppWaiting(struct tcpConnection &conn, streaming chanend app, int appStatus) {
    int x;
    asm(" or %0, %1, %2" : "=r" (x): "r" (app), "r" (app));
    conn.appWaiting = x;
    conn.appStatus = appStatus;
}

static void doClose(struct tcpConnection &conn, streaming chanend app) {
    switch(conn.state) {
    case CLOSED:
        soutct(app, PIP_TCP_ACK_CT); 
        return;
    case SYNSENT:
    case LISTEN:
        conn.opened = 0;
        conn.state = CLOSED;
        soutct(app, PIP_TCP_ACK_CT); 
        return;
    case SYNRCVD:
    case ESTAB:
        conn.state = FINWAIT1;
        pipOutgoingTCP(conn, 0, FIN);
        conn.outgoingSequenceNumber++;
        setAppWaiting(conn, app, APP_CLOSING);
        return;
    case LASTACK:
    case TIMEWAIT:
    case TIMEWAIT0:
    case TIMEWAIT1:
    case TIMEWAIT2:
    case FINWAIT1:
    case FINWAIT2:
    case CLOSING:
        return;
    case CLOSEWAIT:
        conn.state = LASTACK;
        pipOutgoingTCP(conn, 0, FIN);
        conn.outgoingSequenceNumber++;
        setAppWaiting(conn, app, APP_CLOSING);
        return;
    }
}

static void doRead(struct tcpConnection &conn, streaming chanend app) {
    switch(conn.state) {
    case CLOSED:
    case SYNSENT:
    case LISTEN:
    case SYNRCVD:
    case LASTACK:
    case TIMEWAIT:
    case TIMEWAIT0:
    case TIMEWAIT1:
    case TIMEWAIT2:
    case FINWAIT1:
    case FINWAIT2:
    case CLOSING:
        soutct(app, PIP_TCP_ERROR_CT);
        return;
    case ESTAB:
        if (conn.rx.free != BUFFERSIZE) {
            copyDataForRead(conn, app);
        } else {
            setAppWaiting(conn, app, APP_READING);
        }
        return;
    case CLOSEWAIT:
        soutct(app, PIP_TCP_CLOSED_CT);
        return;
    }
}

static void doWrite(struct tcpConnection &conn, streaming chanend app) {
    switch(conn.state) {
    case CLOSED:
    case SYNSENT:
    case LISTEN:
    case SYNRCVD:
    case LASTACK:
    case TIMEWAIT:
    case TIMEWAIT0:
    case TIMEWAIT1:
    case TIMEWAIT2:
    case FINWAIT1:
    case FINWAIT2:
    case CLOSING:
        soutct(app, PIP_TCP_ERROR_CT);
        return;
    case ESTAB:
        if (conn.tx.free != 0) {
            copyDataFromWrite(conn, app);
            loadOutgoingData(conn);
        } else {
            setAppWaiting(conn, app, APP_WRITING);
        }
        return;
    case CLOSEWAIT:
        soutct(app, PIP_TCP_CLOSED_CT);
        return;
    }
}

// Application interface to TCP, comes in two parts
// 1) implemented on the Stack side. (1 function)
// 2) implemented on the Application side. (series of functions)

void pipApplicationTCP(streaming chanend app, int cmd) {
    int connectionNumber;
    app :> connectionNumber;
    switch(cmd) {
    case PIP_TCP_ACCEPT:
        setAppWaiting(tcpConnections[connectionNumber], app, APP_ACCEPTING);
        break;
    case PIP_TCP_CLOSE:
        doClose(tcpConnections[connectionNumber], app);
        break;
    case PIP_TCP_READ:
        doRead(tcpConnections[connectionNumber], app);
        break;
    case PIP_TCP_WRITE:
        doWrite(tcpConnections[connectionNumber], app);
        break;
    }
}


void pipApplicationAccept(streaming chanend stack, unsigned connection) {
    int ack;
    stack <: PIP_TCP_ACCEPT;
    stack <: connection;
    ack = sinct(stack);
}

void pipApplicationClose(streaming chanend stack, unsigned connection) {
    int ack;
    stack <: PIP_TCP_CLOSE;
    stack <: connection;
    ack = sinct(stack);
}

int pipApplicationRead(streaming chanend stack, unsigned connection,
                       unsigned char buffer[], unsigned maxBytes) {
    int ack, actualBytes;
    stack <: PIP_TCP_READ;
    stack <: connection;
#if 0
    while (!stestct(stack)) {
        unsigned char x;
        printstr("FAIL - got token... ");
        stack :> x;
        printintln(x);
    }
#endif
    ack = sinct(stack);
    switch(ack) {
    case PIP_TCP_ACK_CT:
        stack <: maxBytes;
        stack :> actualBytes;
        for(int i = 0; i < actualBytes; i++) {
            stack :> buffer[i];
        }
        return actualBytes;
    case PIP_TCP_ERROR_CT:
        return -1;
    case PIP_TCP_CLOSED_CT:
        return 0;
    }
    printstr("AppRead proto error\n");
    printintln(ack);
    return -1;
}

int pipApplicationWrite(streaming chanend stack, unsigned connection,
                       unsigned char buffer[], unsigned maxBytes) {
    int ack, actualBytes, bytesWritten = 0, start = 0;
    while(maxBytes > 0) {
        stack <: PIP_TCP_WRITE;
        stack <: connection;
#if 0
        while (!stestct(stack)) {
            unsigned char x;
            printstr("FAIL - got token... ");
            stack :> x;
            printintln(x);
        }
#endif
        ack = sinct(stack);
        switch(ack) {
        case PIP_TCP_ACK_CT:
            stack <: maxBytes;
            stack :> actualBytes;
            for(int i = 0; i < actualBytes; i++) {
                stack <: buffer[start + i];
            }
            maxBytes -= actualBytes;
            bytesWritten += actualBytes;
            start += actualBytes;
            break;
        case PIP_TCP_ERROR_CT:
            return -1;
        case PIP_TCP_CLOSED_CT:
            return bytesWritten;
        default:
            printstr("AppWrite proto error\n");
            printintln(ack);
            break;
        }
    }
    return bytesWritten;
}
