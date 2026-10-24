// ------------------------------- //
// -------- Start of File -------- //
// ------------------------------- //
// ----------------------------------------------------------- // 
// C++ Source Code File
// C++ Compiler Used: GNU, Intel
// Produced By: DataReel Software Development Team
// File Creation Date: 07/17/2016
// Date Last Modified: 12/30/2023
// Copyright (c) 2016-2024 DataReel Software Development
// ----------------------------------------------------------- // 
// ------------- Program Description and Details ------------- // 
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
#include "gxdlcode.h"

#include <errno.h>
#include <time.h>
#include <sys/time.h>
#include "m_socket.h"
#include "m_tls.h"

// Process-wide send sequence counter for v2 frames. Incremented
// atomically so every outbound frame carries a unique, increasing
// sequence regardless of which thread sent it.
static volatile uint64_t cm_tx_seq = 0;

// The cluster authkey is the HMAC key. load_hash_key() reads a fixed
// 2048-byte key into servercfg->auth_key, so both ends key identically.
static const int CM_HMAC_KEY_LEN = 2048;

int cm_build_frame(unsigned char *buf, int cap, int cmd,
                   const char *payload, int plen)
{
  if(!buf || cap <= 0) return -1;
  unsigned char nonce[CM_NONCE_LEN];
  if(cm_random_bytes(nonce, CM_NONCE_LEN) != 0) return -1;
  uint64_t seq = __sync_add_and_fetch(&cm_tx_seq, 1);
  uint64_t ts = (uint64_t)time(0);
  size_t out_len = 0;
  cm_frame_status s = cm_frame_build(buf, (size_t)cap, &out_len,
                                     (uint8_t)cmd, CM_FLAG_HAS_TIMESTAMP,
                                     ts, seq, nonce,
                                     (const uint8_t *)payload,
                                     (uint32_t)(plen < 0 ? 0 : plen),
                                     (const uint8_t *)servercfg->auth_key,
                                     CM_HMAC_KEY_LEN);
  if(s != CM_FRAME_OK) return -1;
  return (int)out_len;
}

int cm_parse_frame(const unsigned char *in_buf, int in_len, CMFrame &f)
{
  if(in_len < 0) return CM_FRAME_SHORT;
  return (int)cm_frame_parse(in_buf, (size_t)in_len, &f,
                             (const uint8_t *)servercfg->auth_key,
                             CM_HMAC_KEY_LEN);
}

int cm_recv_frame_timed(gxSocket &client, unsigned char *buf, int cap,
                        int timeout_secs, int timeout_usecs)
{
  // A cluster reply is a single datagram, so it must be read with one
  // recvfrom. The gxSocket RecvFrom()/RemoteRecvFrom() variants loop
  // until the whole buffer is filled, which never completes for a
  // datagram smaller than the buffer. We set a receive timeout so a
  // single recvfrom returns the one reply frame (or times out) and
  // read it with the raw single-datagram call.
  struct timeval tv;
  tv.tv_sec = timeout_secs;
  tv.tv_usec = timeout_usecs;
  client.SetSockOpt(SOL_SOCKET, SO_RCVTIMEO, (char *)&tv, sizeof(tv));
  int n = client.RawReadFrom(buf, cap);
  if(n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
    // Preserve the caller's timeout detection.
    client.SetSocketError(gxSOCKET_REQUEST_TIMEOUT);
  }
  return n;
}

// ----------------------------------------------------------- //
// TCP + TLS client transport (Phase 4).
//
// When cluster_transport is CM_TRANSPORT_TCP, cluster messages ride the
// same v2 authenticated frame but over a mutually-authenticated TLS
// tunnel instead of a UDP datagram. TLS gives confidentiality and peer
// authentication on the wire; the HMAC frame still authenticates every
// message end to end, so a terminated TLS proxy cannot forge a command.
// ----------------------------------------------------------- //

// A single process-wide client TLS context, built lazily from the
// configured cluster CA, certificate and key. Reused for every outbound
// TCP request so the cert/key are parsed once.
static CMTlsContext *cm_client_tls_ctx()
{
  static CMTlsContext ctx;
  static int inited = 0;
  static int ok = 0;
  if(!inited) {
    inited = 1;
    int minor = (servercfg->tls_min_version >= 3) ? 3 : 2;
    if(ctx.init(CM_TLS_CLIENT, servercfg->tls_ca_file.c_str(),
                servercfg->tls_cert_file.c_str(),
                servercfg->tls_key_file.c_str(), minor) == CM_TLS_OK) {
      ok = 1;
    }
  }
  return ok ? &ctx : 0;
}

// Read exactly one v2 frame from a TLS connection into buf (capacity cap).
// The header is read first; magic, version and the declared payload length
// are validated (and the length capped) before the payload is read, so a
// lie in the length field cannot drive a huge or unbounded read. Returns
// the total frame length, or <= 0 on error. The caller still authenticates
// the frame with cm_parse_frame().
int cm_tls_read_frame(CMTlsConn &conn, unsigned char *buf, int cap)
{
  if(cap < CM_FRAME_HDR_LEN) return -1;
  if(conn.read_full(buf, CM_FRAME_HDR_LEN) != CM_TLS_OK) return -1;

  // Header field offsets mirror m_crypto.cpp: magic@0, version@4,
  // payload_len@8 (all little-endian).
  uint32_t magic = (uint32_t)buf[0] | ((uint32_t)buf[1] << 8) |
                   ((uint32_t)buf[2] << 16) | ((uint32_t)buf[3] << 24);
  if(magic != CM_FRAME_MAGIC) return -1;
  if(buf[4] != CM_PROTO_VERSION) return -1;

  uint32_t plen = (uint32_t)buf[8] | ((uint32_t)buf[9] << 8) |
                  ((uint32_t)buf[10] << 16) | ((uint32_t)buf[11] << 24);
  if(plen > (uint32_t)CM_MAX_PAYLOAD) return -1;
  if((int)(CM_FRAME_HDR_LEN + plen) > cap) return -1;
  if(plen > 0) {
    if(conn.read_full(buf + CM_FRAME_HDR_LEN, plen) != CM_TLS_OK) return -1;
  }
  return (int)(CM_FRAME_HDR_LEN + (int)plen);
}

// Open a TLS connection to a node, send one request frame, read one reply
// frame. Returns 0 on success (reply in reply_buf/*reply_len), non-zero on
// any failure (connect, handshake, verify, I/O or timeout).
static int cm_tcp_request(CMnode *node, const unsigned char *frame, int frame_len,
                          unsigned char *reply_buf, int reply_cap, int *reply_len,
                          int timeout_secs)
{
  *reply_len = 0;
  CMTlsContext *tctx = cm_client_tls_ctx();
  if(!tctx) return 1; // CA/cert/key not loaded or invalid

  gxSocket sock(SOCK_STREAM, servercfg->tcpport, node->keep_alive_ip.c_str());
  if(!sock) return 1;

  struct timeval tv;
  tv.tv_sec = timeout_secs;
  tv.tv_usec = 0;
  sock.SetSockOpt(SOL_SOCKET, SO_RCVTIMEO, (char *)&tv, sizeof(tv));
  sock.SetSockOpt(SOL_SOCKET, SO_SNDTIMEO, (char *)&tv, sizeof(tv));

  if(sock.Connect() < 0) { sock.Close(); return 1; }

  CMTlsConn conn;
  const char *fp = node->tls_peer_fingerprint.is_null() ? 0
                     : node->tls_peer_fingerprint.c_str();
  if(conn.start(tctx, sock.GetSocket(), fp) != CM_TLS_OK) {
    sock.Close();
    return 1;
  }
  int rc = 1;
  if(conn.write_full(frame, frame_len) == CM_TLS_OK) {
    int n = cm_tls_read_frame(conn, reply_buf, reply_cap);
    if(n > 0) { *reply_len = n; rc = 0; }
  }
  conn.shutdown_conn();
  sock.Close();
  return rc;
}

// Transport-aware request/response used by every client command. Builds an
// authenticated v2 frame for cmd (+optional payload), sends it over UDP or
// TCP+TLS per servercfg->cluster_transport, and returns the authenticated
// reply frame in reply_buf. Returns 0 on success; on a UDP timeout sets
// *timed_out so callers can distinguish it from other failures.
int cm_node_exchange(CMnode *node, int cmd, const char *payload, int plen,
                     unsigned char *reply_buf, int reply_cap, int *reply_len,
                     int timeout_secs, int *timed_out)
{
  if(timed_out) *timed_out = 0;
  if(reply_len) *reply_len = 0;

  unsigned char txbuf[CM_RX_BUF_SIZE];
  int flen = cm_build_frame(txbuf, sizeof(txbuf), cmd, payload, plen);
  if(flen < 0) return 1;

  if(servercfg->cluster_transport == CM_TRANSPORT_TCP) {
    return cm_tcp_request(node, txbuf, flen, reply_buf, reply_cap,
                          reply_len, timeout_secs);
  }

  // Default UDP datagram transport.
  gxSocket client(SOCK_DGRAM, servercfg->udpport, node->keep_alive_ip.c_str());
  if(!client) return 1;
  int optVal = 1;
  client.SetSockOpt(SOL_SOCKET, SO_REUSEADDR, (char *)&optVal, sizeof(optVal));
  if(client.SendTo(txbuf, flen) != flen) return 1;
  int n = cm_recv_frame_timed(client, reply_buf, reply_cap, timeout_secs, 0);
  if(n <= 0) {
    if(timed_out && client.GetSocketError() == gxSOCKET_REQUEST_TIMEOUT)
      *timed_out = 1;
    return 1;
  }
  if(reply_len) *reply_len = n;
  return 0;
}

// Witness-based quorum check (Phase 4).
//
// In a two-node cluster a broken link between the peers looks exactly like
// a dead peer, so both sides could try to own the resources at once
// (split brain / false failover). When quorum_required is set, a node may
// only take over resources if it still has quorum: it must be able to
// reach the witness. Reaching the witness but not the peer means this node
// is in the majority partition (itself + witness) and may fail over;
// failing to reach the witness as well means this node is probably the
// isolated minority and must stand down. This directly blocks an attacker
// or a network cut from triggering a bogus failover.
//
// The witness is any reachable DRCM endpoint that answers the
// authenticated v2 protocol over the configured transport. Returns 1 if
// quorum is held (or the feature is off), 0 if this node must stand down.
int cm_have_quorum()
{
  if(!servercfg->quorum_required) return 1; // feature disabled: always allowed
  if(servercfg->witness_endpoint.is_null()) return 0; // required but unset: fail closed

  // witness_endpoint may be "host" or "host:port"; the witness listens on
  // the cluster's standard port, so only the host part is used here.
  gxString host = servercfg->witness_endpoint;
  if(host.Find(":") != -1) host.DeleteAfterIncluding(":");
  host.TrimLeading(' '); host.TrimTrailing(' ');
  if(host.is_null()) return 0;

  CMnode witness;
  witness.keep_alive_ip = host;

  unsigned char reply[CM_RX_BUF_SIZE];
  int reply_len = 0;
  if(cm_node_exchange(&witness, CM_CMD_PING, 0, 0, reply, sizeof(reply),
                      &reply_len, 2, 0) != 0 || reply_len <= 0) {
    return 0; // cannot reach the witness -> no quorum
  }
  CMFrame rf;
  if(cm_parse_frame(reply, reply_len, rf) != CM_FRAME_OK || rf.command != CM_CMD_ACK)
    return 0; // witness did not authenticate -> no quorum
  return 1;
}

int get_fd_socket_error(int &error_number, gxString &sbuf)
{
  error_number = errno;
  return fd_error_to_string(error_number, sbuf);
}

CM_MessageHeader::CM_MessageHeader() 
{ 
  clear(); 
  set_word(checkword, NET_CHECKWORD); 
}

void CM_MessageHeader::clear() 
{ 
  memset(checkword, 0, 4);
  memset(bytes, 0, 4);
  memset(datagram_size, 0, 4);
  memset(cluster_command, 0, 4);
  set_word(datagram_size, 1500);
  memset(sha1sum, 0, 40);
}

void CM_MessageHeader::copy(const CM_MessageHeader &ob) 
{
  memmove(checkword, ob.checkword, 4);
  memmove(bytes, ob.bytes, 4);
  memmove(datagram_size, ob.datagram_size, 4);
  memmove(cluster_command, ob.cluster_command, 4);
  memmove(sha1sum, ob.sha1sum, 40);
}

int CM_MessageHeader::get_word(char bytes[4])
{
  // Assemble as unsigned so a high byte does not shift a negative value
  unsigned int a, b, c, d;
  a = (unsigned char)bytes[0];
  b = (unsigned char)bytes[1];
  c = (unsigned char)bytes[2];
  d = (unsigned char)bytes[3];
  return (int)(a | (b << 8) | (c << 16) | (d << 24));
}

void CM_MessageHeader::set_word(char bytes[4], int val)
{
  bytes[0] = (unsigned char)(val & 0xFF);
  bytes[1] = (unsigned char)((val & 0xFF00)>>8);
  bytes[2] = (unsigned char)((val & 0xFF0000)>>16);
  bytes[3] = (unsigned char)((val & 0xFF000000)>>24);
}

CM_MessageHeader::CM_MessageHeader(const CM_MessageHeader &ob) 
{ 
  copy(ob); 
}

CM_MessageHeader &CM_MessageHeader::operator=(const CM_MessageHeader &ob) 
{ 
  if(this != &ob) {
    copy(ob);
  }
  return *this;
}

// Map error number to a string. NOTE: This is not a 
// redundent function. The errno values have different
// meanings for files, threads, sockets, etc. Also, the
// errno to string functions vary on Linux platforms.
// In order to remain consistent on all Linux varients
// and return string values for socket connections
// use this function to get the string value for errno
// following a socket call.
//
// Developers, if you find string messages that need to
// be changed, modifed and submit to git repo.
int fd_error_to_string(int error_number, gxString &sbuf)
{
  switch(error_number) {
    case 0:
      sbuf << clear << "Success";
      break;
    case EPERM: 
      sbuf << clear << "EPERM: Operation not permitted";
      break;
    case ENOENT:
      // sbuf << clear << "ENOENT: No such file or directory";
      sbuf << clear << "ENOENT: Cannot open another socket connection";
      break;
    case ESRCH:
      sbuf << clear << "ESRCH: No such process";
      break;
    case EINTR:
      sbuf << clear << "EINTR: Interrupted system call";
      break;
    case EIO:
      sbuf << clear << "EIO: I/O error";
      break;
    case ENXIO:
      sbuf << clear << "ENXIO: No such device or address";
      break;
    case E2BIG:
      sbuf << clear << "E2BIG: Argument list too long";
      break;
    case ENOEXEC:
      sbuf << clear << "ENOEXEC: Exec format error";
      break;
    case EBADF:
      sbuf << clear << "EBADF: Socket file decriptor is closed";
      break;
    case ECHILD:
      sbuf << clear << "ECHILD: No child processes";
      break;
      // For sockets use EWOULDBLOCK
      //case EAGAIN:
      //  sbuf << clear << "EAGAIN: Try again";
      //  break;
    case ENOMEM:
      sbuf << clear << "ENOMEM: Out of memory";
      break;
    case EACCES:
      sbuf << clear << "EACCES: Permission denied";
      break;
    case EFAULT:
      sbuf << clear << "EFAULT: Bad address";
      break;
    case ENOTBLK:
      sbuf << clear << "ENOTBLK: Block device required";
      break;
    case EBUSY:
      sbuf << clear << "EBUSY: Device or resource busy";
      break;
    case EEXIST:
      sbuf << clear << "EEXIST: File exists";
      break;
    case EXDEV:
      sbuf << clear << "EXDEV: Cross-device link";
      break;
    case ENODEV:
      sbuf << clear << "ENODEV: No such device";
      break;
    case ENOTDIR:
      sbuf << clear << "ENOTDIR: Not a directory";
      break;
    case EISDIR:
      sbuf << clear << "EISDIR: Is a directory";
      break;
    case EINVAL:
      sbuf << clear << "EINVAL: Invalid argument";
      break;
    case ENFILE:
      sbuf << clear << "ENFILE: File table overflow";
      break;
    case EMFILE:
      sbuf << clear << "EMFILE: Too many open files";
      break;
    case ENOTTY:
      sbuf << clear << "ENOTTY: Not a typewriter";
      break;
    case ETXTBSY:
      sbuf << clear << "ETXTBSY: Text file busy";
      break;
    case EFBIG:
      sbuf << clear << "EFBIG: File too large";
      break;
    case ENOSPC:
      sbuf << clear << "ENOSPC: No space left on device";
      break;
    case ESPIPE:
      sbuf << clear << "ESPIPE: Illegal seek";
      break;
    case EROFS:
      sbuf << clear << "EROFS: Read-only file system";
      break;
    case EMLINK:
      sbuf << clear << "EMLINK: Too many links";
      break;
    case EPIPE:
      sbuf << clear << "EPIPE: Broken pipe";
      break;
    case EDOM:
      sbuf << clear << "EDOM: Math argument out of domain of func";
      break;
    case ERANGE:
      sbuf << clear << "ERANGE: Math result not representable";
      break;
    case EDEADLK:
      sbuf << clear << "EDEADLK: Resource deadlock would occur";
      break;
    case ENAMETOOLONG:
      sbuf << clear << "ENAMETOOLONG: File name too long";
      break;
    case ENOLCK:
      sbuf << clear << "ENOLCK: No record locks available";
      break;
    case ENOSYS:
      sbuf << clear << "ENOSYS: Function not implemented";
      break;
    case ENOTEMPTY:
      sbuf << clear << "ENOTEMPTY: Directory not empty";
      break;
    case ELOOP:
      sbuf << clear << "ELOOP: Too many symbolic links encountered";
      break;
    case EWOULDBLOCK:
      sbuf << clear << "EWOULDBLOCK: Operation would block";
      break;
    case ENOMSG:
      sbuf << clear << "ENOMSG: No message of desired type";
      break;
    case EIDRM:
      sbuf << clear << "EIDRM: Identifier removed";
      break;
    case ECHRNG:
      sbuf << clear << "ECHRNG: Channel number out of range";
      break;
    case EL2NSYNC:
      sbuf << clear << "EL2NSYNC: Level 2 not synchronized";
      break;
    case EL3HLT:
      sbuf << clear << "EL3HLT: Level 3 halted";
      break;
    case EL3RST:
      sbuf << clear << "EL3RST: Level 3 reset";
      break;
    case ELNRNG:
      sbuf << clear << "ELNRNG: Link number out of range";
      break;
    case EUNATCH:
      sbuf << clear << "EUNATCH: Protocol driver not attached";
      break;
    case ENOCSI:
      sbuf << clear << "ENOCSI: No CSI structure available";
      break;
    case EL2HLT:
      sbuf << clear << "EL2HLT: Level 2 halted";
      break;
    case EBADE:
      sbuf << clear << "EBADE: Invalid exchange";
      break;
    case EBADR:
      sbuf << clear << "EBADR: Invalid request descriptor";
      break;
    case EXFULL:
      sbuf << clear << "EXFULL: Exchange full";
      break;
    case ENOANO:
      sbuf << clear << "ENOANO: No anode";
      break;
    case EBADRQC:
      sbuf << clear << "EBADRQC: Invalid request code";
      break;
    case EBADSLT:
      sbuf << clear << "EBADSLT: Invalid slot";
      break;
    // case EDEADLOCK:
    //   sbuf << clear << "EDEADLOCK: Bad font file format";
    //   break;
    case ENOSTR:
      sbuf << clear << "ENOSTR: Device not a stream";
      break;
    case ENODATA:
      sbuf << clear << "ENODATA: No data available";
      break;
    case ETIME:
      sbuf << clear << "ETIME: Timer expired";
      break;
    case ENOSR:
      sbuf << clear << "ENOSR: Out of streams resources";
      break;
    case ENONET:
      sbuf << clear << "ENONET: Machine is not on the network";
      break;
    case ENOPKG:
      sbuf << clear << "ENOPKG: Package not installed";
      break;
    case EREMOTE:
      sbuf << clear << "EREMOTE: Object is remote";
      break;
    case ENOLINK:
      sbuf << clear << "ENOLINK: Link has been severed";
      break;
    case EADV:
      sbuf << clear << "EADV: Advertise error";
      break;
    case ESRMNT:
      sbuf << clear << "ESRMNT: Srmount error";
      break;
    case ECOMM:
      sbuf << clear << "ECOMM: Communication error on send";
      break;
    case EPROTO:
      sbuf << clear << "EPROTO: Protocol error";
      break;
    case EMULTIHOP:
      sbuf << clear << "EMULTIHOP: Multihop attempted";
      break;
    case EDOTDOT:
      sbuf << clear << "EDOTDOT: RFS specific error";
      break;
    case EBADMSG:
      sbuf << clear << "EBADMSG: Not a data message";
      break;
    case EOVERFLOW:
      sbuf << clear << "EOVERFLOW: Value too large for defined data type";
      break;
    case ENOTUNIQ:
      sbuf << clear << "ENOTUNIQ: Name not unique on network";
      break;
    case EBADFD:
      sbuf << clear << "EBADFD: File descriptor in bad state";
      break;
    case EREMCHG:
      sbuf << clear << "EREMCHG: Remote address changed";
      break;
    case ELIBACC:
      sbuf << clear << "ELIBACC: Can not access a needed shared library";
      break;
    case ELIBBAD:
      sbuf << clear << "ELIBBAD: Accessing a corrupted shared library";
      break;
    case ELIBSCN:
      sbuf << clear << "ELIBSCN: .lib section in a.out corrupted";
      break;
    case ELIBMAX:
      sbuf << clear << "ELIBMAX: Attempting to link in too many shared libraries";
      break;
    case ELIBEXEC:
      sbuf << clear << "ELIBEXEC: Cannot exec a shared library directly";
      break;
    case EILSEQ:
      sbuf << clear << "EILSEQ: Illegal byte sequence";
      break;
    case ERESTART:
      sbuf << clear << "ERESTART: Interrupted system call should be restarted";
      break;
    case ESTRPIPE:
      sbuf << clear << "ESTRPIPE: Streams pipe error";
      break;
    case EUSERS:
      sbuf << clear << "EUSERS: Too many users";
      break;
    case ENOTSOCK:
      sbuf << clear << "ENOTSOCK: Socket operation on non-socket";
      break;
    case EDESTADDRREQ:
      sbuf << clear << "EDESTADDRREQ: Destination address required";
      break;
    case EMSGSIZE:
      sbuf << clear << "EMSGSIZE: Message too long";
      break;
    case EPROTOTYPE:
      sbuf << clear << "EPROTOTYPE: Protocol wrong type for socket";
      break;
    case ENOPROTOOPT:
      sbuf << clear << "ENOPROTOOPT: Protocol not available";
      break;
    case EPROTONOSUPPORT:
      sbuf << clear << "EPROTONOSUPPORT: Protocol not supported";
      break;
    case ESOCKTNOSUPPORT:
      sbuf << clear << "ESOCKTNOSUPPORT: Socket type not supported";
      break;
    case EOPNOTSUPP:
      sbuf << clear << "EOPNOTSUPP: Operation not supported on transport endpoint";
      break;
    case EPFNOSUPPORT:
      sbuf << clear << "EPFNOSUPPORT: Protocol family not supported";
      break;
    case EAFNOSUPPORT:
      sbuf << clear << "EAFNOSUPPORT: Address family not supported by protocol";
      break;
    case EADDRINUSE:
      sbuf << clear << "EADDRINUSE: Address already in use";
      break;
    case EADDRNOTAVAIL:
      sbuf << clear << "EADDRNOTAVAIL: Cannot assign requested address";
      break;
    case ENETDOWN:
      sbuf << clear << "ENETDOWN: Network is down";
      break;
    case ENETUNREACH:
      sbuf << clear << "ENETUNREACH: Network is unreachable";
      break;
    case ENETRESET:
      sbuf << clear << "ENETRESET: Network dropped connection because of reset";
      break;
    case ECONNABORTED:
      sbuf << clear << "ECONNABORTED: Software caused connection abort";
      break;
    case ECONNRESET:
      sbuf << clear << "ECONNRESET: Connection reset by peer";
      break;
    case ENOBUFS:
      sbuf << clear << "ENOBUFS: No buffer space available";
      break;
    case EISCONN:
      sbuf << clear << "EISCONN: Transport endpoint is already connected";
      break;
    case ENOTCONN:
      sbuf << clear << "ENOTCONN: Transport endpoint is not connected";
      break;
    case ESHUTDOWN:
      sbuf << clear << "ESHUTDOWN: Cannot send after transport endpoint shutdown";
      break;
    case ETOOMANYREFS:
      sbuf << clear << "ETOOMANYREFS: Too many references: cannot splice";
      break;
    case ETIMEDOUT:
      sbuf << clear << "ETIMEDOUT: Connection timed out";
      break;
    case ECONNREFUSED:
      sbuf << clear << "ECONNREFUSED: Connection refused";
      break;
    case EHOSTDOWN:
      sbuf << clear << "EHOSTDOWN: Host is down";
      break;
    case EHOSTUNREACH:
      sbuf << clear << "EHOSTUNREACH: No route to host";
      break;
    case EALREADY:
      sbuf << clear << "EALREADY: Operation already in progress";
      break;
    case EINPROGRESS:
      sbuf << clear << "EINPROGRESS: Operation now in progress";
      break;
    case ESTALE:
      sbuf << clear << "ESTALE: Stale file handle";
      break;
    case EUCLEAN:
      sbuf << clear << "EUCLEAN: Structure needs cleaning";
      break;
    case ENOTNAM:
      sbuf << clear << "ENOTNAM: Not a XENIX named type file";
      break;
    case ENAVAIL:
      sbuf << clear << "ENAVAIL: No XENIX semaphores available";
      break;
    case EISNAM:
      sbuf << clear << "EISNAM: Is a named type file";
      break;
    case EREMOTEIO:
      sbuf << clear << "EREMOTEIO: Remote I/O error";
      break;
    case EDQUOT:
      sbuf << clear << "EDQUOT: Quota exceeded";
      break;
    case ENOMEDIUM:
      sbuf << clear << "ENOMEDIUM: No medium found";
      break;
    case EMEDIUMTYPE:
      sbuf << clear << "EMEDIUMTYPE: Wrong medium type";
      break;
    case ECANCELED:
      sbuf << clear << "ECANCELED: Operation Canceled";
      break;
    case ENOKEY:
      sbuf << clear << "ENOKEY: Required key not available";
      break;
    case EKEYEXPIRED:
      sbuf << clear << "EKEYEXPIRED: Key has expired";
      break;
    case EKEYREVOKED:
      sbuf << clear << "EKEYREVOKED: Key has been revoked";
      break;
    case EKEYREJECTED:
      sbuf << clear << "EKEYREJECTED: Key was rejected by service";
      break;
    case EOWNERDEAD:
      sbuf << clear << "EOWNERDEAD: Owner died";
      break;
    case ENOTRECOVERABLE:
      sbuf << clear << "ENOTRECOVERABLE: State not recoverable";
      break;
    case ERFKILL:
      sbuf << clear << "ERFKILL: Operation not possible due to RF-kill";
      break;
    case EHWPOISON:
      sbuf << clear << "EHWPOISON: Memory page has hardware error";
      break;
    default:
      sbuf << clear << "UNKNOWN: An unkown error occured";
      break;
  }
  return error_number;
}

int cm_reply_is_valid(CM_MessageHeader &cmhdr)
{
  if(cmhdr.get_word(cmhdr.checkword) != NET_CHECKWORD) return 0;
  if(memcmp(cmhdr.sha1sum, servercfg->sha1sum, sizeof(cmhdr.sha1sum)) != 0) return 0;
  if(cmhdr.get_word(cmhdr.cluster_command) != CM_CMD_ACK) return 0;
  return 1;
}

// Return 0 for pass, 1 for fail
// error_level = -1 for fatal error
// error_level = 1 for socket write error
// error_level = 2 for read timeout error
// error_level = 3 for read error
int send_keep_alive(CMnode *n, int &error_level, int timeout_secs, int timeout_usecs)
{
  gxString message;
  error_level = 0;

  // Transport-aware keep alive: an authenticated KEEPALIVE frame over UDP
  // or TCP+TLS per servercfg->cluster_transport. The reply must
  // authenticate (valid HMAC) and be an ACK.
  unsigned char rxbuf[CM_RX_BUF_SIZE];
  int bytes_read = 0;
  int timed_out = 0;
  int rc = cm_node_exchange(n, CM_CMD_KEEPALIVE, 0, 0, rxbuf, sizeof(rxbuf),
                            &bytes_read, timeout_secs, &timed_out);
  if(rc != 0 || bytes_read <= 0) {
    // For UDP a clean timeout maps to error_level 2 (the keep alive logic
    // treats a timeout as a missed heartbeat); any other failure is 3.
    error_level = timed_out ? 2 : 3;
    if(servercfg->debug && servercfg->debug_level >= 5 && servercfg->verbose_level >= 5) {
      if(timed_out)
	message << clear << "ERROR - Receive timeout reading CM reply from " << n->keep_alive_ip.c_str();
      else
	message << clear << "ERROR - Error exchanging CM keep alive with " << n->keep_alive_ip.c_str();
      LogDebugMessage(message.c_str());
    }
    return 1;
  }

  // Only count a reply that authenticates (valid HMAC) and is an ACK.
  CMFrame reply;
  if(cm_parse_frame(rxbuf, bytes_read, reply) != CM_FRAME_OK ||
     reply.command != CM_CMD_ACK) {
    if(servercfg->debug && servercfg->debug_level >= 5 && servercfg->verbose_level >= 5) {
      message << clear << "ERROR - Bad or unauthenticated keep alive reply from " << n->keep_alive_ip.c_str();
      LogDebugMessage(message.c_str());
    }
    error_level = 3;
    return 1;
  }

  return 0;
}
// ----------------------------------------------------------- // 
// ------------------------------- //
// --------- End of File --------- //
// ------------------------------- //
