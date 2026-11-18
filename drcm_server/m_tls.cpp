// ----------------------------------------------------------- //
// DRCM TLS transport helper. See m_tls.h for the design notes.
//
// Targets OpenSSL 1.1.1 (RHEL 8) and 3.x (RHEL 9/10). A couple of
// functions are deprecated in 3.0 but present in both; the deprecation
// warning is silenced locally rather than forking the code per version.
// ----------------------------------------------------------- //
#include "m_tls.h"

#include <string.h>
#include <stdio.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/x509.h>
#include <openssl/evp.h>
#include <openssl/crypto.h>
#include <openssl/objects.h>

static void set_err(char *dst, size_t n, const char *msg)
{
  unsigned long e = ERR_get_error();
  if(e) {
    char ebuf[160];
    ERR_error_string_n(e, ebuf, sizeof(ebuf));
    snprintf(dst, n, "%s: %s", msg, ebuf);
  } else {
    snprintf(dst, n, "%s", msg);
  }
}

// Normalize a fingerprint string to lowercase hex with no separators.
static void normalize_fp(const char *in, char *out, size_t out_n)
{
  size_t j = 0;
  for(size_t i = 0; in[i] && j + 1 < out_n; i++) {
    char c = in[i];
    if(c == ':' || c == ' ') continue;
    if(c >= 'A' && c <= 'F') c = (char)(c - 'A' + 'a');
    out[j++] = c;
  }
  out[j] = '\0';
}

void cm_tls_normalize_fingerprint(const char *in, char *out, size_t out_n)
{
  char tmp[160];
  normalize_fp(in ? in : "", tmp, sizeof(tmp));
  const char *w = tmp;
  if(strncmp(w, "sha256", 6) == 0) w += 6;
  snprintf(out, out_n, "%s", w);
}

int cm_tls_has_mlkem()
{
  static int known = -1;
  if(known < 0) {
    known = 0;
    SSL_CTX *t = SSL_CTX_new(TLS_method());
    if(t) {
      if(SSL_CTX_set1_groups_list(t, CM_TLS_PQ_GROUP) == 1) known = 1;
      SSL_CTX_free(t);
    }
    ERR_clear_error();
  }
  return known;
}

const char *cm_tls_library_version()
{
  return OpenSSL_version(OPENSSL_VERSION);
}

int cm_tls_resolve_groups(const char *configured, int pq_only,
                          char *out, size_t out_n, char *err, size_t err_n)
{
  if(err && err_n) err[0] = '\0';
  int mlkem = cm_tls_has_mlkem();
  if(pq_only) {
    if(!mlkem) {
      snprintf(err, err_n, "tls_pq_only needs OpenSSL 3.5 or later with %s; this build uses %s",
               CM_TLS_PQ_GROUP, cm_tls_library_version());
      return -1;
    }
    if(configured && configured[0] && strcmp(configured, CM_TLS_PQ_GROUP) != 0) {
      snprintf(err, err_n, "tls_pq_only allows only tls_groups = %s", CM_TLS_PQ_GROUP);
      return -1;
    }
    snprintf(out, out_n, "%s", CM_TLS_PQ_GROUP);
    return 0;
  }
  if(!configured || !configured[0]) {
    snprintf(out, out_n, "%s", mlkem ? CM_TLS_GROUPS_DEFAULT : CM_TLS_GROUPS_CLASSIC);
    return 0;
  }
  // Check the list against the linked library
  SSL_CTX *t = SSL_CTX_new(TLS_method());
  int ok = t && SSL_CTX_set1_groups_list(t, configured) == 1;
  if(t) SSL_CTX_free(t);
  ERR_clear_error();
  if(!ok) {
    snprintf(err, err_n, "tls_groups \"%s\" is not supported by %s%s", configured,
             cm_tls_library_version(),
             mlkem ? "" : " (ML-KEM groups need OpenSSL 3.5 or later)");
    return -1;
  }
  snprintf(out, out_n, "%s", configured);
  return 0;
}

CMTlsContext::CMTlsContext() : ctx(0), role(CM_TLS_CLIENT) { err_[0] = '\0'; }

CMTlsContext::~CMTlsContext() { free_ctx(); }

void CMTlsContext::free_ctx()
{
  if(ctx) { SSL_CTX_free(ctx); ctx = 0; }
}

cm_tls_status CMTlsContext::init(cm_tls_role r,
                                 const char *ca_file,
                                 const char *cert_file,
                                 const char *key_file,
                                 int min_tls_minor,
                                 const char *groups)
{
  role = r;
  err_[0] = '\0';
  if(!ca_file || !cert_file || !key_file) {
    snprintf(err_, sizeof(err_), "missing ca/cert/key file path");
    return CM_TLS_EARG;
  }

  const SSL_METHOD *method = TLS_method();
  ctx = SSL_CTX_new(method);
  if(!ctx) { set_err(err_, sizeof(err_), "SSL_CTX_new failed"); return CM_TLS_EINIT; }

  int ver = (min_tls_minor >= 3) ? TLS1_3_VERSION : TLS1_2_VERSION;
  if(SSL_CTX_set_min_proto_version(ctx, ver) != 1) {
    set_err(err_, sizeof(err_), "set_min_proto_version failed");
    free_ctx(); return CM_TLS_EINIT;
  }

  // Key exchange groups (ML-KEM hybrid first when the library has it)
  if(groups && groups[0] && SSL_CTX_set1_groups_list(ctx, groups) != 1) {
    set_err(err_, sizeof(err_), "set1_groups_list failed");
    free_ctx(); return CM_TLS_EINIT;
  }

  // Load the cluster CA and require the peer to present a cert signed by
  // it. This is what keeps an unauthenticated peer out of the cluster.
  if(SSL_CTX_load_verify_locations(ctx, ca_file, NULL) != 1) {
    set_err(err_, sizeof(err_), "load CA file failed");
    free_ctx(); return CM_TLS_ECERT;
  }
  if(SSL_CTX_use_certificate_chain_file(ctx, cert_file) != 1) {
    set_err(err_, sizeof(err_), "load certificate failed");
    free_ctx(); return CM_TLS_ECERT;
  }
  if(SSL_CTX_use_PrivateKey_file(ctx, key_file, SSL_FILETYPE_PEM) != 1) {
    set_err(err_, sizeof(err_), "load private key failed");
    free_ctx(); return CM_TLS_ECERT;
  }
  if(SSL_CTX_check_private_key(ctx) != 1) {
    set_err(err_, sizeof(err_), "private key does not match certificate");
    free_ctx(); return CM_TLS_ECERT;
  }

  // Mutual authentication: both client and server verify the peer and
  // fail the handshake if no valid cert is presented.
  SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT, NULL);
  SSL_CTX_set_verify_depth(ctx, 4);
  return CM_TLS_OK;
}

CMTlsConn::CMTlsConn() : ssl(0), fd(-1)
{
  err_[0] = '\0'; peer_subject_[0] = '\0'; peer_fp_[0] = '\0';
  tls_version_[0] = '\0'; tls_group_[0] = '\0';
}

CMTlsConn::~CMTlsConn()
{
  if(ssl) { SSL_free(ssl); ssl = 0; }
}

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
static X509 *get_peer_cert(SSL *ssl)
{
  // SSL_get_peer_certificate (1.1.1) == SSL_get1_peer_certificate (3.0);
  // both bump the ref count, so the caller frees it.
  return SSL_get_peer_certificate(ssl);
}
#pragma GCC diagnostic pop

cm_tls_status CMTlsConn::start(CMTlsContext *tctx, int sock_fd,
                               const char *required_fingerprint)
{
  err_[0] = '\0';
  if(!tctx || !tctx->ctx || sock_fd < 0) {
    snprintf(err_, sizeof(err_), "bad TLS context or fd");
    return CM_TLS_EARG;
  }
  fd = sock_fd;
  ssl = SSL_new(tctx->ctx);
  if(!ssl) { set_err(err_, sizeof(err_), "SSL_new failed"); return CM_TLS_EINIT; }
  if(SSL_set_fd(ssl, fd) != 1) {
    set_err(err_, sizeof(err_), "SSL_set_fd failed");
    return CM_TLS_EINIT;
  }

  int rc = (tctx->role == CM_TLS_SERVER) ? SSL_accept(ssl) : SSL_connect(ssl);
  if(rc != 1) {
    set_err(err_, sizeof(err_), "TLS handshake failed");
    return CM_TLS_EHANDSHAKE;
  }

  // CA verification already happened during the handshake; confirm the
  // result explicitly so a misconfiguration cannot slip through.
  long vr = SSL_get_verify_result(ssl);
  if(vr != X509_V_OK) {
    snprintf(err_, sizeof(err_), "peer certificate verify failed (%ld)", vr);
    return CM_TLS_EHANDSHAKE;
  }

  // Record what was negotiated, for the log
  snprintf(tls_version_, sizeof(tls_version_), "%s", SSL_get_version(ssl));
#if OPENSSL_VERSION_NUMBER >= 0x30200000L
  {
    const char *g = SSL_get0_group_name(ssl);
    snprintf(tls_group_, sizeof(tls_group_), "%s", g ? g : "unknown");
  }
#elif OPENSSL_VERSION_NUMBER >= 0x30000000L
  {
    int nid = SSL_get_negotiated_group(ssl);
    const char *g = (nid && !(nid & TLSEXT_nid_unknown)) ? OBJ_nid2sn(nid) : 0;
    snprintf(tls_group_, sizeof(tls_group_), "%s", g ? g : "unknown");
  }
#else
  snprintf(tls_group_, sizeof(tls_group_), "%s", "unknown (OpenSSL 1.1.1)");
#endif

  X509 *peer = get_peer_cert(ssl);
  if(!peer) {
    snprintf(err_, sizeof(err_), "peer presented no certificate");
    return CM_TLS_EHANDSHAKE;
  }

  X509_NAME *subj = X509_get_subject_name(peer);
  if(subj) X509_NAME_oneline(subj, peer_subject_, sizeof(peer_subject_));

  // Keep the peer's fingerprint, so a request can be tied to the node
  // whose tls_peer_fingerprint it matches
  {
    unsigned char pmd[EVP_MAX_MD_SIZE]; unsigned int pmdlen = 0;
    if(X509_digest(peer, EVP_sha256(), pmd, &pmdlen) == 1) {
      size_t j = 0;
      for(unsigned int i = 0; i < pmdlen && j + 2 < sizeof(peer_fp_); i++)
	j += (size_t)snprintf(peer_fp_ + j, sizeof(peer_fp_) - j, "%02x", pmd[i]);
    }
  }

  // Optional certificate pinning: require an exact SHA-256 fingerprint.
  if(required_fingerprint && required_fingerprint[0]) {
    unsigned char md[EVP_MAX_MD_SIZE]; unsigned int mdlen = 0;
    char want[160], got[2 * EVP_MAX_MD_SIZE + 1];
    char want_norm[160];
    normalize_fp(required_fingerprint, want_norm, sizeof(want_norm));
    // strip an optional "sha256:" prefix
    const char *w = want_norm;
    if(strncmp(w, "sha256", 6) == 0) w += 6;
    snprintf(want, sizeof(want), "%s", w);
    if(X509_digest(peer, EVP_sha256(), md, &mdlen) == 1) {
      size_t j = 0;
      for(unsigned int i = 0; i < mdlen && j + 2 < sizeof(got); i++)
        j += (size_t)snprintf(got + j, sizeof(got) - j, "%02x", md[i]);
      if(strcmp(got, want) != 0) {
        snprintf(err_, sizeof(err_), "peer fingerprint mismatch");
        X509_free(peer);
        return CM_TLS_EHANDSHAKE;
      }
    }
  }

  X509_free(peer);
  return CM_TLS_OK;
}

cm_tls_status CMTlsConn::read_full(void *buf, size_t len)
{
  err_[0] = '\0';
  size_t got = 0;
  while(got < len) {
    int n = SSL_read(ssl, (char *)buf + got, (int)(len - got));
    if(n <= 0) {
      set_err(err_, sizeof(err_), "SSL_read failed or connection closed");
      return CM_TLS_EIO;
    }
    got += (size_t)n;
  }
  return CM_TLS_OK;
}

cm_tls_status CMTlsConn::write_full(const void *buf, size_t len)
{
  err_[0] = '\0';
  size_t sent = 0;
  while(sent < len) {
    int n = SSL_write(ssl, (const char *)buf + sent, (int)(len - sent));
    if(n <= 0) {
      set_err(err_, sizeof(err_), "SSL_write failed");
      return CM_TLS_EIO;
    }
    sent += (size_t)n;
  }
  return CM_TLS_OK;
}

void CMTlsConn::shutdown_conn()
{
  if(ssl) {
    SSL_shutdown(ssl);
    SSL_free(ssl);
    ssl = 0;
  }
}
