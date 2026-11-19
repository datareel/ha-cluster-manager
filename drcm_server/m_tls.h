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

// Normalize a fingerprint (colon separated or plain, any case, optional
// "sha256" prefix) to lowercase hex with no separators.
void cm_tls_normalize_fingerprint(const char *in, char *out, size_t out_n);

// Post-quantum key exchange (1.49). OpenSSL 3.5 and later offer the hybrid
// ML-KEM group X25519MLKEM768 for TLS 1.3. The default group list puts it
// first and keeps X25519 for peers without it. Without ML-KEM (OpenSSL
// before 3.5, such as RHEL 8's 1.1.1) or in FIPS mode, DRCM sets no group
// list and the system crypto policy decides. tls_pq_only = 1 allows
// X25519MLKEM768 alone and forces TLS 1.3 (both ends need OpenSSL 3.5+,
// FIPS mode off).
#define CM_TLS_PQ_GROUP        "X25519MLKEM768"
#define CM_TLS_GROUPS_DEFAULT  "X25519MLKEM768:X25519"
// FIPS mode with an OpenSSL that does not read the RHEL system crypto
// policy (static or custom builds): FIPS-approved groups only
#define CM_TLS_GROUPS_FIPS     "P-256:P-384:P-521"

// 1 if the linked OpenSSL can use the ML-KEM hybrid group
int cm_tls_has_mlkem();
// 1 if the system or OpenSSL runs in FIPS mode (/proc/sys/crypto/fips_enabled
// or the OpenSSL default properties). In FIPS mode DRCM does not set its own
// group list; the system crypto policy chooses approved groups.
int cm_tls_fips_mode();
// How OpenSSL is linked: "system" (the OS library), "static" (built in) or
// "custom" (another shared OpenSSL, OPENSSL_PC / OPENSSL_PREFIX)
const char *cm_tls_flavor();
// 1 if the linked OpenSSL follows the RHEL system crypto policy (the OS
// library); static and custom builds do not read it
int cm_tls_follows_system_policy();
// The linked OpenSSL version text, e.g. "OpenSSL 3.5.9 30 Sep 2026"
const char *cm_tls_library_version();
// The group list to use for a configured value (empty = default) and mode.
// Returns 0 and fills out (an empty out = use the system crypto policy and
// OpenSSL defaults), or -1 with a reason in err.
int cm_tls_resolve_groups(const char *configured, int pq_only,
                          char *out, size_t out_n, char *err, size_t err_n);

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
                     int min_tls_minor /* 2 or 3 */,
                     const char *groups = 0 /* resolved list, 0 = library default */);
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
  // SHA-256 of the peer certificate, lowercase hex, no separators
  const char *peer_fingerprint() const { return peer_fp_; }
  // Negotiated protocol (e.g. "TLSv1.3") and key exchange group (e.g.
  // "X25519MLKEM768"), set after a successful start()
  const char *tls_version() const { return tls_version_; }
  const char *tls_group() const { return tls_group_; }

  SSL *ssl;
  int  fd;
  char err_[256];
  char peer_subject_[256];
  char peer_fp_[2 * 64 + 1];
  char tls_version_[32];
  char tls_group_[64];
};

#endif // __DRCM_TLS_HPP__
