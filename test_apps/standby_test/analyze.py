#!/usr/bin/env python3
"""Reads shared/events.log from the standby tests and reports, for each
resource, every time it moved between nodes inside a test window: the
gap (no node ran it) and any overlap (two nodes ran it at once).

Usage: analyze.py events.log START_MARK [END_MARK]
Exit status 1 if any resource ran on two nodes at once in the window.
"""
import sys

def main():
    path, start = sys.argv[1], sys.argv[2]
    end = sys.argv[3] if len(sys.argv) > 3 else None
    owners = {}      # resource -> set of hosts
    empty_since = {} # resource -> ms when its last owner stopped
    in_window = False
    t0 = None
    overlap = 0
    for line in open(path):
        f = line.split()
        if len(f) < 3:
            continue
        ms = int(f[0])
        if f[1] == "MARK":
            if f[2] == start:
                in_window, t0 = True, ms
                print(f"window {start}")
            elif end and f[2] == end:
                in_window = False
            continue
        host, rtype, name, action = f[1], f[2], f[3], f[4]
        res = f"{rtype}:{name}"
        cur = owners.setdefault(res, set())
        if action == "start":
            if in_window:
                when = (ms - t0) / 1000.0
                if cur:
                    overlap += 1
                    print(f"  OVERLAP {res}: started on {host} at +{when:.1f}s while running on {','.join(sorted(cur))}")
                elif res in empty_since:
                    gap = (ms - empty_since[res]) / 1000.0
                    print(f"  {res}: started on {host} at +{when:.1f}s, gap {gap:.1f}s with no owner")
                else:
                    print(f"  {res}: started on {host} at +{when:.1f}s")
            cur.add(host)
            empty_since.pop(res, None)
        else:
            cur.discard(host)
            if in_window:
                print(f"  {res}: stopped on {host} at +{(ms - t0) / 1000.0:.1f}s")
            if not cur:
                empty_since[res] = ms
    return 1 if overlap else 0

if __name__ == "__main__":
    sys.exit(main())
