// ------------------------------- //
// -------- Start of File -------- //
// ------------------------------- //
// ----------------------------------------------------------- //
// C++ Header File
// C++ Compiler Used: GNU, Intel
// Produced By: DataReel Software Development Team
// File Creation Date: 07/17/2016
// Date Last Modified: 12/30/2023
// Copyright (c) 2016-2024 DataReel Software Development
// ----------------------------------------------------------- // 
// ---------- Include File Description and Details  ---------- // 
// ----------------------------------------------------------- // 
/*
This file is part of the DataReel software distribution.

Datareel is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation, either version 3 of the License, or (at your
option) any later version. 

Datareel software is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with the DataReel software distribution.  If not, see
<http://www.gnu.org/licenses/>.

Extra socket functions for Datareel cluster manager.

*/
// ----------------------------------------------------------- //   
#ifndef __DRCM_SOCKET_HPP__
#define __DRCM_SOCKET_HPP__

#include "gxdlcode.h"
#include "drcm_server.h"
#include "m_crypto.h"

const int NET_CHECKWORD = 0X1010FEFE;
const int DEFAULT_PORT = 53897;
const int DEFAULT_TCP_PORT = 53898; // TCP+TLS mode listen port (Phase 4)
const int DEFAULT_TIMEOUT = 300;
const int DEFAULT_TIMEOUT_US = 0;
const int DEFAULT_DATAGRAM_SIZE = 1500;

enum CM_CMD { // Cluster Manager Commands
  CM_CMD_NAK = 0,
  CM_CMD_ACK,
  CM_CMD_PING,
  CM_CMD_KEEPALIVE,
  CM_CMD_GETSTATS
};

const char DEFAULT_DATAGRAM_FILL = 'X';

struct CM_MessageHeader {
  CM_MessageHeader();
  ~CM_MessageHeader() { }
  CM_MessageHeader(const CM_MessageHeader &ob);
  CM_MessageHeader &operator=(const CM_MessageHeader &ob);

  void clear();
  void copy(const CM_MessageHeader &ob);
  int get_word(char bytes[4]);
  void set_word(char bytes[4], int val);

  char checkword[4];
  char bytes[4];
  char datagram_size[4];
  char cluster_command[4];
  char sha1sum[40];
};

// Client socket type used to associate client sockets other data types.
struct CMClientSocket_t
{
  CMClientSocket_t() {
    seq_num = 0;
    r_port = 1;
    client_socket = -1;
  }
  ~CMClientSocket_t() { }

  gxsSocket_t client_socket;
  int seq_num; // Sequence number for log entries
  gxString client_name;
  int r_port;
  CM_MessageHeader cmhdr;
};

// Send a keep alive message to a CM node
// Return 0 for pass, 1 for fail
// error_level = -1 for fatal error
// error_level = 1 for socket write error
// error_level = 2 for read timeout error
// error_level = 3 for read error
int send_keep_alive(CMnode *n, int &error_level, int timeout_secs = 1, int timeout_usecs = 0);


// Returns 1 if a reply header has our checkword, auth hash and an ACK
int cm_reply_is_valid(CM_MessageHeader &cmhdr);

// Largest stats buffer a node will accept in one UDP datagram
const int CM_MAX_STATS_SIZE = 65507;

// ----------------------------------------------------------- //
// DRCM v2 authenticated frame helpers (Phase 4).
//
// All cluster messages are now carried in the HMAC-authenticated frame
// defined in m_crypto.h, keyed with the cluster authkey. These helpers
// build and verify frames for both the UDP and the TCP transports.
// ----------------------------------------------------------- //

// A receive buffer sized for the largest possible frame.
const int CM_RX_BUF_SIZE = (int)(CM_FRAME_HDR_LEN + CM_MAX_PAYLOAD);

// Build an authenticated frame into buf (capacity cap). cmd is a CM_CMD
// value; payload/plen may be NULL/0. A fresh nonce, the current time and
// a process-wide increasing sequence number are filled in. Returns the
// total frame length, or -1 on error.
int cm_build_frame(unsigned char *buf, int cap, int cmd,
                   const char *payload, int plen);

// Parse and authenticate a received datagram/frame of in_len bytes into
// f, using the cluster authkey. Returns a cm_frame_status.
int cm_parse_frame(const unsigned char *in_buf, int in_len, CMFrame &f);

// Receive a single reply datagram (one frame) from a client socket with
// a timeout. A cluster reply is always one datagram, so it is read with a
// single recvfrom (the looping RecvFrom variants never complete for a
// datagram smaller than the supplied buffer). Returns the number of bytes
// read, or <= 0 on timeout/error; on timeout the socket error is set to
// gxSOCKET_REQUEST_TIMEOUT so callers can distinguish it.
int cm_recv_frame_timed(gxSocket &client, unsigned char *buf, int cap,
                        int timeout_secs, int timeout_usecs);

// Forward declaration so the TCP frame reader can be declared without
// pulling OpenSSL into every includer.
struct CMTlsConn;

// Read exactly one complete v2 frame from a TLS connection into buf
// (capacity cap). Validates magic/version and caps the declared payload
// length before reading it. Returns the total frame length, or <= 0 on
// error. The caller authenticates the frame with cm_parse_frame().
int cm_tls_read_frame(CMTlsConn &conn, unsigned char *buf, int cap);

// Transport-aware cluster request/response. Builds an authenticated v2
// frame for cmd (with optional payload), sends it over UDP or TCP+TLS
// according to servercfg->cluster_transport, and returns the peer's
// authenticated reply frame in reply_buf/*reply_len. Returns 0 on
// success; on a UDP timeout sets *timed_out (may be NULL). The caller
// authenticates the reply with cm_parse_frame().
int cm_node_exchange(CMnode *node, int cmd, const char *payload, int plen,
                     unsigned char *reply_buf, int reply_cap, int *reply_len,
                     int timeout_secs, int *timed_out);

// Witness-based quorum check. Returns 1 if this node holds quorum and may
// take over cluster resources, 0 if it must stand down (cannot reach the
// configured witness). Always returns 1 when quorum_required is not set.
// Prevents a two-node split brain from causing a false failover.
int cm_have_quorum();

// Get string value for errno. Returns the error_number provided by caller
int fd_error_to_string(int error_number, gxString &sbuf);


#endif // __DRCM_SOCKET_HPP__
// ----------------------------------------------------------- // 
// ------------------------------- //
// --------- End of File --------- //
// ------------------------------- //
