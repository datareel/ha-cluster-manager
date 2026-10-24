// ----------------------------------------------------------- //
// DRCM authenticated message frame and anti-replay layer.
// See m_crypto.h for the design notes and the frame layout.
// ----------------------------------------------------------- //
#include "m_crypto.h"

#include <string.h>
#include <openssl/hmac.h>
#include <openssl/rand.h>
#include <openssl/crypto.h>

// Frame header byte layout (all integers little-endian):
//   off  size  field
//     0     4  magic (CM_FRAME_MAGIC)
//     4     1  version
//     5     1  command
//     6     1  flags
//     7     1  reserved (0)
//     8     4  payload_len
//    12     8  timestamp
//    20     8  sequence
//    28    16  nonce
//    44    32  hmac (computed with these 32 bytes set to zero)
//   = 76 bytes, then payload_len bytes of payload.
static const size_t OFF_MAGIC     = 0;
static const size_t OFF_VERSION   = 4;
static const size_t OFF_COMMAND   = 5;
static const size_t OFF_FLAGS     = 6;
static const size_t OFF_RESERVED  = 7;
static const size_t OFF_PAYLEN    = 8;
static const size_t OFF_TIMESTAMP = 12;
static const size_t OFF_SEQUENCE  = 20;
static const size_t OFF_NONCE     = 28;
static const size_t OFF_HMAC      = 44;

static void put_u32(uint8_t *p, uint32_t v)
{
  p[0] = (uint8_t)(v & 0xFF);
  p[1] = (uint8_t)((v >> 8) & 0xFF);
  p[2] = (uint8_t)((v >> 16) & 0xFF);
  p[3] = (uint8_t)((v >> 24) & 0xFF);
}

static uint32_t get_u32(const uint8_t *p)
{
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
         ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void put_u64(uint8_t *p, uint64_t v)
{
  for(int i = 0; i < 8; i++) p[i] = (uint8_t)((v >> (8 * i)) & 0xFF);
}

static uint64_t get_u64(const uint8_t *p)
{
  uint64_t v = 0;
  for(int i = 0; i < 8; i++) v |= ((uint64_t)p[i]) << (8 * i);
  return v;
}

// Compute HMAC-SHA256 over the frame with the hmac field treated as
// zero, into out32. frame must be at least CM_FRAME_HDR_LEN bytes and
// hold header + payload contiguously (total_len bytes).
//
// The HMAC_CTX API is used because it is available and identical on
// OpenSSL 1.1.1 (RHEL 8) and 3.x (RHEL 9/10). It is marked deprecated
// on 3.0 only; the EVP_MAC replacement does not exist on 1.1.1. The
// deprecation warning is silenced locally rather than forking per
// version.
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
static int compute_hmac(const uint8_t *frame, size_t total_len,
                        const uint8_t *key, size_t key_len,
                        uint8_t out32[CM_HMAC_LEN])
{
  // HMAC the bytes before the hmac field, a run of 32 zero bytes in
  // place of the hmac field, then everything after it (payload).
  static const uint8_t zero_hmac[CM_HMAC_LEN] = {0};
  unsigned int outlen = 0;
  HMAC_CTX *ctx = HMAC_CTX_new();
  if(!ctx) return -1;
  int rc = -1;
  if(HMAC_Init_ex(ctx, key, (int)key_len, EVP_sha256(), NULL) == 1 &&
     HMAC_Update(ctx, frame, OFF_HMAC) == 1 &&
     HMAC_Update(ctx, zero_hmac, CM_HMAC_LEN) == 1 &&
     HMAC_Update(ctx, frame + OFF_HMAC + CM_HMAC_LEN,
                 total_len - (OFF_HMAC + CM_HMAC_LEN)) == 1 &&
     HMAC_Final(ctx, out32, &outlen) == 1 &&
     outlen == CM_HMAC_LEN) {
    rc = 0;
  }
  HMAC_CTX_free(ctx);
  return rc;
}
#pragma GCC diagnostic pop

cm_frame_status cm_frame_build(uint8_t *out_buf, size_t out_cap, size_t *out_len,
                               uint8_t command, uint8_t flags,
                               uint64_t timestamp, uint64_t sequence,
                               const uint8_t nonce[CM_NONCE_LEN],
                               const uint8_t *payload, uint32_t payload_len,
                               const uint8_t *key, size_t key_len)
{
  if(payload_len > CM_MAX_PAYLOAD) return CM_FRAME_PAYLOAD_TOO_BIG;
  size_t total = CM_FRAME_HDR_LEN + payload_len;
  if(out_cap < total) return CM_FRAME_SHORT;

  memset(out_buf, 0, CM_FRAME_HDR_LEN);
  put_u32(out_buf + OFF_MAGIC, CM_FRAME_MAGIC);
  out_buf[OFF_VERSION]  = CM_PROTO_VERSION;
  out_buf[OFF_COMMAND]  = command;
  out_buf[OFF_FLAGS]    = flags;
  out_buf[OFF_RESERVED] = 0;
  put_u32(out_buf + OFF_PAYLEN, payload_len);
  put_u64(out_buf + OFF_TIMESTAMP, timestamp);
  put_u64(out_buf + OFF_SEQUENCE, sequence);
  memcpy(out_buf + OFF_NONCE, nonce, CM_NONCE_LEN);
  // hmac field left zero for now
  if(payload_len && payload) memcpy(out_buf + CM_FRAME_HDR_LEN, payload, payload_len);

  uint8_t mac[CM_HMAC_LEN];
  if(compute_hmac(out_buf, total, key, key_len, mac) != 0) return CM_FRAME_BAD_HMAC;
  memcpy(out_buf + OFF_HMAC, mac, CM_HMAC_LEN);

  if(out_len) *out_len = total;
  return CM_FRAME_OK;
}

cm_frame_status cm_frame_parse(const uint8_t *in_buf, size_t in_len,
                               CMFrame *out,
                               const uint8_t *key, size_t key_len)
{
  if(in_len < CM_FRAME_HDR_LEN) return CM_FRAME_SHORT;
  if(get_u32(in_buf + OFF_MAGIC) != CM_FRAME_MAGIC) return CM_FRAME_BAD_MAGIC;
  if(in_buf[OFF_VERSION] != CM_PROTO_VERSION) return CM_FRAME_BAD_VERSION;

  uint32_t plen = get_u32(in_buf + OFF_PAYLEN);
  if(plen > CM_MAX_PAYLOAD) return CM_FRAME_PAYLOAD_TOO_BIG;
  size_t total = CM_FRAME_HDR_LEN + (size_t)plen;
  if(in_len < total) return CM_FRAME_SHORT;

  // Verify the HMAC in constant time before trusting any field.
  uint8_t mac[CM_HMAC_LEN];
  if(compute_hmac(in_buf, total, key, key_len, mac) != 0) return CM_FRAME_BAD_HMAC;
  if(CRYPTO_memcmp(mac, in_buf + OFF_HMAC, CM_HMAC_LEN) != 0) return CM_FRAME_BAD_HMAC;

  if(out) {
    out->version     = in_buf[OFF_VERSION];
    out->command     = in_buf[OFF_COMMAND];
    out->flags       = in_buf[OFF_FLAGS];
    out->payload_len = plen;
    out->timestamp   = get_u64(in_buf + OFF_TIMESTAMP);
    out->sequence    = get_u64(in_buf + OFF_SEQUENCE);
    memcpy(out->nonce, in_buf + OFF_NONCE, CM_NONCE_LEN);
    out->payload     = plen ? (in_buf + CM_FRAME_HDR_LEN) : NULL;
  }
  return CM_FRAME_OK;
}

int cm_random_bytes(uint8_t *buf, size_t len)
{
  return RAND_bytes(buf, (int)len) == 1 ? 0 : -1;
}

CMReplayState::CMReplayState()
{
  reset();
}

void CMReplayState::reset()
{
  highest_seq = 0;
  have_seq = 0;
  strict_sequence = 0;
  use_timestamp = 0;
  window_secs = 30;
  nonce_count = 0;
  nonce_pos = 0;
  memset(nonces, 0, sizeof(nonces));
}

cm_frame_status cm_replay_check(CMReplayState *st, const CMFrame *f,
                                uint64_t now_secs)
{
  if(!st || !f) return CM_FRAME_REPLAY;

  // 1. Reject an exact replay: a nonce we have seen recently. Clock-free.
  for(int i = 0; i < st->nonce_count; i++) {
    if(memcmp(st->nonces[i], f->nonce, CM_NONCE_LEN) == 0) return CM_FRAME_REPLAY;
  }

  // 2. Optional strict sequence (TCP connection epoch).
  if(st->strict_sequence && st->have_seq && f->sequence <= st->highest_seq)
    return CM_FRAME_REPLAY;

  // 3. Optional timestamp window for sites with synced clocks.
  if(st->use_timestamp && (f->flags & CM_FLAG_HAS_TIMESTAMP)) {
    uint64_t lo = (now_secs > st->window_secs) ? now_secs - st->window_secs : 0;
    uint64_t hi = now_secs + st->window_secs;
    if(f->timestamp < lo || f->timestamp > hi) return CM_FRAME_REPLAY;
  }

  // Accept: record the nonce in the ring and advance the sequence.
  memcpy(st->nonces[st->nonce_pos], f->nonce, CM_NONCE_LEN);
  st->nonce_pos = (st->nonce_pos + 1) % CM_NONCE_CACHE;
  if(st->nonce_count < CM_NONCE_CACHE) st->nonce_count++;
  if(!st->have_seq || f->sequence > st->highest_seq) st->highest_seq = f->sequence;
  st->have_seq = 1;
  return CM_FRAME_OK;
}
