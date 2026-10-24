// ----------------------------------------------------------- //
// DRCM TLS transport helper.
//
// A thin wrapper over OpenSSL that gives the TCP transport mutually
// authenticated, encrypted connections. Both ends present a
// certificate signed by the cluster CA and verify the peer against
// that CA. TLS 1.2 is the floor. Certificates may be self-signed by a
// cluster CA (default) or issued externally (e.g. Let's Encrypt via
// acme.sh); the config only names the cert, key and CA files, so the
// source does not matter here.
//
// This wrapper keeps DataReel types out so it can be tested on its own.
// It owns the SSL_CTX and per-connection SSL objects but not the
// underlying socket fd, which the caller creates and closes.
// ----------------------------------------------------------- //
#ifndef __DRCM_TLS_HPP__
#define __DRCM_TLS_HPP__

#include <stddef.h>

// Opaque forward declarations so callers need not include OpenSSL.
typedef struct ssl_ctx_st SSL_CTX;
typedef struct ssl_st SSL;

enum cm_tls_role { CM_TLS_CLIENT = 0, CM_TLS_SERVER = 1 };

enum cm_tls_status {
  CM_TLS_OK = 0,
  CM_TLS_EINIT,       // context/library init failed
  CM_TLS_ECERT,       // cert/key/CA load failed
  CM_TLS_EHANDSHAKE,  // TLS handshake failed (includes peer verify failure)
  CM_TLS_EIO,         // read/write error or clean peer close
  CM_TLS_EARG
};

// One TLS context, shared by all connections of the same role.
// optional_peer_fingerprint, when non-NULL, is an extra check beyond CA
// verification: the peer cert's SHA-256 fingerprint must equal it
// (hex, colon-separated or plain). min_tls is 12 or 13 for 1.2 / 1.3.
struct CMTlsContext {
  CMTlsContext();
  ~CMTlsContext();

  cm_tls_status init(cm_tls_role role,
                     const char *ca_file,
                     const char *cert_file,
                     const char *key_file,
                     int min_tls_minor /* 2 or 3 */);
  void free_ctx();

  const char *last_error() const { return err_; }

  SSL_CTX *ctx;
  cm_tls_role role;
  char err_[256];
};

// One TLS connection over an already-connected socket fd.
struct CMTlsConn {
  CMTlsConn();
  ~CMTlsConn();

  // Wrap fd and perform the handshake. For a server, fd is the accepted
  // socket; for a client, the connected socket. On a verify failure the
  // handshake fails closed. required_fingerprint is optional (see above).
  cm_tls_status start(CMTlsContext *tctx, int fd,
                      const char *required_fingerprint);

  // Blocking read/write of exactly len bytes (TLS records may fragment).
  // Return CM_TLS_OK with *done set, or an error.
  cm_tls_status read_full(void *buf, size_t len);
  cm_tls_status write_full(const void *buf, size_t len);

  void shutdown_conn();

  const char *last_error() const { return err_; }
  const char *peer_subject() const { return peer_subject_; }

  SSL *ssl;
  int  fd;
  char err_[256];
  char peer_subject_[256];
};

#endif // __DRCM_TLS_HPP__
