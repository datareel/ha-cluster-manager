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
// The checks, in order:
//  1. Nonce cache: a frame whose random nonce was seen recently is
//     rejected. This catches an exact replayed datagram without any
//     clock sync, so it is the baseline protection for UDP, where the
//     commands are read-only/liveness and a peer may restart.
//  2. Strict sequence (strict_sequence=1, used on a TCP connection):
//     the sequence number must strictly increase. A TCP connection is a
//     fresh epoch, so a reset on reconnect is fine. Left off for UDP,
//     where a peer restart legitimately resets the counter.
//  3. Timestamp window (use_timestamp=1, dougg's optional stricter
//     mode): the frame timestamp must be within window_secs of now.
//     Needs loosely synced clocks (chrony/ntp).
// ----------------------------------------------------------- //
const int CM_NONCE_CACHE = 256; // recent nonces remembered per peer

struct CMReplayState {
  CMReplayState();

  uint64_t highest_seq;      // highest accepted sequence from this peer
  int      have_seq;         // 0 until the first frame is accepted
  int      strict_sequence;  // 1 to enforce strictly increasing sequence
  int      use_timestamp;    // 1 to also enforce the timestamp window
  uint32_t window_secs;      // allowed clock skew when use_timestamp

  uint8_t  nonces[CM_NONCE_CACHE][CM_NONCE_LEN];
  int      nonce_count;      // number of valid entries (grows to CM_NONCE_CACHE)
  int      nonce_pos;        // next write position (ring)

  void reset();
};

// Check a parsed frame against the peer's replay state. now_secs is the
// receiver's current unix time (used only when use_timestamp). On
// CM_FRAME_OK the state is advanced (nonce recorded, sequence updated).
// Returns CM_FRAME_OK or CM_FRAME_REPLAY.
cm_frame_status cm_replay_check(CMReplayState *st, const CMFrame *f,
                                uint64_t now_secs);

#endif // __DRCM_CRYPTO_HPP__
