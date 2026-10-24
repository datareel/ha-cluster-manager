// ----------------------------------------------------------- //
// DRCM authenticated message frame and anti-replay layer.
//
// This module defines the version 2 DRCM wire frame, which replaces
// the version 1 CM_MessageHeader. Every frame carries an
// HMAC-SHA256 over its whole contents keyed with the cluster authkey,
// plus a timestamp, a per-peer monotonic sequence number and a random
// nonce so a captured frame cannot be replayed or altered.
//
// It is deliberately free of DataReel types so it can be unit tested
// on its own and reused by both the UDP and the TCP transports.
// ----------------------------------------------------------- //
#ifndef __DRCM_CRYPTO_HPP__
#define __DRCM_CRYPTO_HPP__

#include <stdint.h>
#include <stddef.h>

// Wire constants
const uint32_t CM_FRAME_MAGIC   = 0x1010FEFE; // matches the v1 checkword
const uint8_t  CM_PROTO_VERSION = 2;
const size_t   CM_NONCE_LEN     = 16;
const size_t   CM_HMAC_LEN      = 32;         // HMAC-SHA256 output
const size_t   CM_FRAME_HDR_LEN = 76;         // fixed header, see layout below
// Largest payload accepted in one frame. Matches the UDP datagram cap
// and bounds every allocation made from a frame length field.
const uint32_t CM_MAX_PAYLOAD   = 65507;

// Frame flags
const uint8_t  CM_FLAG_HAS_TIMESTAMP = 0x01;  // timestamp field is meaningful

// Parse / verify result codes
enum cm_frame_status {
  CM_FRAME_OK = 0,
  CM_FRAME_SHORT,         // buffer smaller than the fixed header or claimed payload
  CM_FRAME_BAD_MAGIC,
  CM_FRAME_BAD_VERSION,
  CM_FRAME_PAYLOAD_TOO_BIG,
  CM_FRAME_BAD_HMAC,      // authentication failed
  CM_FRAME_REPLAY         // failed the anti-replay check
};

// A decoded frame. The payload pointer, when returned by the parser,
// points into the caller's input buffer; it is not copied.
struct CMFrame {
  uint8_t  version;
  uint8_t  command;
  uint8_t  flags;
  uint32_t payload_len;
  uint64_t timestamp;     // unix seconds, meaningful only if CM_FLAG_HAS_TIMESTAMP
  uint64_t sequence;      // per-peer monotonic counter
  uint8_t  nonce[CM_NONCE_LEN];
  const uint8_t *payload; // into the input buffer (parse) or caller's data (build)
};

// Build a frame into out_buf. out_buf must hold at least
// CM_FRAME_HDR_LEN + payload_len bytes. On success *out_len is the
// total frame size. Returns CM_FRAME_OK or an error code.
cm_frame_status cm_frame_build(uint8_t *out_buf, size_t out_cap, size_t *out_len,
                               uint8_t command, uint8_t flags,
                               uint64_t timestamp, uint64_t sequence,
                               const uint8_t nonce[CM_NONCE_LEN],
                               const uint8_t *payload, uint32_t payload_len,
                               const uint8_t *key, size_t key_len);

// Parse and authenticate a frame from in_buf. Checks the magic, the
// version, the payload bound and the HMAC (in constant time). Fills
// out. Does NOT perform the anti-replay check; call cm_replay_check
// after a successful parse. Returns CM_FRAME_OK or an error code.
cm_frame_status cm_frame_parse(const uint8_t *in_buf, size_t in_len,
                               CMFrame *out,
                               const uint8_t *key, size_t key_len);

// Fill buf with cryptographically strong random bytes. Returns 0 on
// success, non-zero on failure.
int cm_random_bytes(uint8_t *buf, size_t len);

// ----------------------------------------------------------- //
// Anti-replay state for one peer.
//
// Default policy (dougg's choice): accept a frame only if its sequence
// number is strictly greater than the highest seen from this peer. A
// captured frame therefore cannot be resent. The optional timestamp
// window adds a second check for sites that run synced clocks.
// ----------------------------------------------------------- //
struct CMReplayState {
  CMReplayState();

  uint64_t highest_seq;      // highest accepted sequence from this peer
  int      have_seq;         // 0 until the first frame is accepted
  int      use_timestamp;    // 1 to also enforce the timestamp window
  uint32_t window_secs;      // allowed clock skew when use_timestamp

  void reset();
};

// Check a parsed frame against the peer's replay state. now_secs is the
// receiver's current unix time (used only when use_timestamp). On
// CM_FRAME_OK the state is advanced to this frame's sequence. Returns
// CM_FRAME_OK or CM_FRAME_REPLAY.
cm_frame_status cm_replay_check(CMReplayState *st, const CMFrame *f,
                                uint64_t now_secs);

#endif // __DRCM_CRYPTO_HPP__
