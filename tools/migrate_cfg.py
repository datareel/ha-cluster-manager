#!/usr/bin/env python3
"""Migrate a pre-Phase-4 DRCM cm.cfg to the new configuration format.

The Phase 4 release adds optional keys to the [CM_SERVER] section for the
TCP + TLS transport, anti-replay tuning and witness quorum. An old config
still loads (every new key has a safe default), so this tool is additive:
it copies the original file through unchanged and inserts the new keys into
[CM_SERVER] if they are not already there. By default it leaves the cluster
on the UDP transport (identical behaviour to before); pass --tcp to switch
it to TCP + TLS and scaffold the TLS and quorum settings.

Usage:
  migrate_cfg.py OLD.cfg [-o NEW.cfg] [--tcp] [--witness HOST[:PORT]]
                 [--ca FILE] [--cert FILE] [--key FILE] [--tls-min 1.2|1.3]
                 [--replay-window SECONDS] [--quorum]

With no -o the migrated config is written to stdout. The tool is idempotent:
re-running it on an already-migrated file changes nothing.
"""
import argparse
import sys

PHASE4_KEYS = (
    "cluster_transport", "tls_ca_file", "tls_cert_file", "tls_key_file",
    "tls_min_version", "replay_window_secs", "quorum_required",
    "witness_endpoint",
)

BANNER = "# ---- Phase 4: transport / TLS / anti-replay / quorum ----"


def parse_args(argv):
    p = argparse.ArgumentParser(description="Migrate an old DRCM cm.cfg to the Phase 4 format.")
    p.add_argument("old", help="path to the existing (old) cm.cfg")
    p.add_argument("-o", "--out", help="output file (default: stdout)")
    p.add_argument("--tcp", action="store_true",
                   help="switch the cluster to the TCP + TLS transport")
    p.add_argument("--witness", default="",
                   help="witness endpoint HOST[:PORT] for quorum (implies a witness)")
    p.add_argument("--ca", default="/etc/drcm/tls/ca.pem", help="cluster CA file")
    p.add_argument("--cert", default="/etc/drcm/tls/node.pem", help="this node's certificate")
    p.add_argument("--key", default="/etc/drcm/tls/node-key.pem", help="this node's private key")
    p.add_argument("--tls-min", default="1.2", choices=["1.2", "1.3"],
                   help="minimum TLS version (default 1.2)")
    p.add_argument("--replay-window", type=int, default=0, metavar="SECONDS",
                   help="timestamp anti-replay window in seconds (0 = sequence/nonce only, default)")
    p.add_argument("--quorum", action="store_true",
                   help="require witness quorum before a failover (needs --witness)")
    return p.parse_args(argv)


def build_phase4_block(args):
    """Return the Phase 4 key lines to insert into [CM_SERVER]."""
    transport = "tcp" if args.tcp else "udp"
    quorum = 1 if args.quorum else 0
    lines = [
        BANNER,
        "# Transport: 'udp' (same-subnet clusters, default) or 'tcp' (TLS over the internet).",
        "cluster_transport = %s" % transport,
    ]
    if args.tcp:
        lines += [
            "# TLS material. Self-signed cluster CA is fine; externally-issued",
            "# certs (e.g. Let's Encrypt via acme.sh) work too -- only the files matter.",
            "tls_ca_file = %s" % args.ca,
            "tls_cert_file = %s" % args.cert,
            "tls_key_file = %s" % args.key,
            "tls_min_version = %s" % args.tls_min,
        ]
    else:
        lines += [
            "# TLS files are only used when cluster_transport = tcp:",
            "# tls_ca_file = %s" % args.ca,
            "# tls_cert_file = %s" % args.cert,
            "# tls_key_file = %s" % args.key,
            "# tls_min_version = %s" % args.tls_min,
        ]
    lines += [
        "# Anti-replay: sequence + per-message nonce always on. A non-zero",
        "# window also enforces a timestamp check (requires synced clocks).",
        "replay_window_secs = %d" % args.replay_window,
        "# Witness quorum blocks a two-node split brain from a false failover.",
        "quorum_required = %d" % quorum,
    ]
    if args.witness:
        lines.append("witness_endpoint = %s" % args.witness)
    else:
        lines.append("# witness_endpoint = 10.0.0.9   # a reachable DRCM endpoint used as the quorum witness")
    return [l + "\n" for l in lines]


def migrate(text, args):
    lines = text.splitlines(keepends=True)

    # Which Phase 4 keys are already present (as real settings, not comments)?
    present = set()
    for ln in lines:
        s = ln.strip()
        if not s or s.startswith("#"):
            continue
        if "=" in s:
            k = s.split("=", 1)[0].strip()
            if k in PHASE4_KEYS:
                present.add(k)

    # Already migrated (has cluster_transport): optionally flip transport, else no-op.
    if "cluster_transport" in present:
        out = []
        for ln in lines:
            s = ln.strip()
            if args.tcp and s and not s.startswith("#") and s.split("=", 1)[0].strip() == "cluster_transport":
                indent = ln[:len(ln) - len(ln.lstrip())]
                out.append("%scluster_transport = tcp\n" % indent)
            else:
                out.append(ln)
        return "".join(out)

    # Find the [CM_SERVER] section and the line where it ends (next [SECTION]
    # or EOF); insert the Phase 4 block just before that.
    out = []
    i = 0
    n = len(lines)
    inserted = False
    in_server = False
    while i < n:
        ln = lines[i]
        s = ln.strip()
        if s.startswith("[") and s.endswith("]"):
            if in_server and not inserted:
                out.append("\n")
                out.extend(build_phase4_block(args))
                out.append("\n")
                inserted = True
            in_server = (s == "[CM_SERVER]")
        out.append(ln)
        i += 1

    if in_server and not inserted:  # [CM_SERVER] was the last section
        out.append("\n")
        out.extend(build_phase4_block(args))
        inserted = True

    if not inserted:
        sys.stderr.write("WARNING - no [CM_SERVER] section found; Phase 4 keys were not inserted\n")
    return "".join(out)


def main(argv):
    args = parse_args(argv)
    if args.quorum and not args.witness:
        sys.stderr.write("WARNING - --quorum set without --witness; add a witness_endpoint before enabling quorum\n")
    try:
        with open(args.old, "r") as f:
            text = f.read()
    except OSError as e:
        sys.stderr.write("ERROR - cannot read %s: %s\n" % (args.old, e))
        return 1

    migrated = migrate(text, args)

    if args.out:
        try:
            with open(args.out, "w") as f:
                f.write(migrated)
        except OSError as e:
            sys.stderr.write("ERROR - cannot write %s: %s\n" % (args.out, e))
            return 1
        sys.stderr.write("Wrote migrated config to %s\n" % args.out)
    else:
        sys.stdout.write(migrated)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
