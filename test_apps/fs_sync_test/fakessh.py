#!/usr/bin/python3
# Test stand-in for ssh (client) and sshd (server: fakessh.py --serve)
import sys, os, socket, struct, subprocess, threading, json
PORT = 2222
ALIASES = {"drcm-ws": "ws", "drcm-aws": "aws"}
def send(sock, lock, t, data):
    with lock: sock.sendall(struct.pack("!BI", t, len(data)) + data)
def recvall(sock, n):
    b = b""
    while len(b) < n:
        c = sock.recv(n - len(b))
        if not c: return None
        b += c
    return b
def serve():
    srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", PORT)); srv.listen(20)
    while True:
        c, _ = srv.accept()
        threading.Thread(target=handle, args=(c,), daemon=True).start()
def handle(c):
    f = c.makefile("rb"); hdr = json.loads(f.readline())
    p = subprocess.Popen(["bash", "-c", hdr["cmd"]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    lock = threading.Lock()
    def pump(src, t):
        while True:
            d = os.read(src.fileno(), 65536)
            if not d: break
            send(c, lock, t, d)
    ts = [threading.Thread(target=pump, args=(p.stdout, 1)), threading.Thread(target=pump, args=(p.stderr, 2))]
    for t in ts: t.start()
    def inp():
        try:
            while True:
                h = f.read(5)
                if not h or len(h) < 5: break
                t, n = struct.unpack("!BI", h)
                if n == 0: break
                p.stdin.write(f.read(n)); p.stdin.flush()
        except Exception: pass
        try: p.stdin.close()
        except Exception: pass
    threading.Thread(target=inp, daemon=True).start()
    rc = p.wait()
    for t in ts: t.join()
    send(c, lock, 3, str(rc).encode()); c.close()
def client(argv):
    args = list(argv); nostdin = False; i = 0
    while i < len(args) and args[i].startswith("-"):
        a = args[i]
        if a == "-n": nostdin = True
        if a in ("-o", "-p", "-i", "-l", "-F"): i += 1
        i += 1
    host = args[i]; cmd = " ".join(args[i+1:])
    host = ALIASES.get(host.split("@")[-1], host.split("@")[-1])
    try: s = socket.create_connection((host, PORT), timeout=10)
    except Exception as e:
        sys.stderr.write("fakessh: connect to %s failed: %s\n" % (host, e)); sys.exit(255)
    s.settimeout(None)
    s.sendall((json.dumps({"cmd": cmd}) + "\n").encode()); lock = threading.Lock()
    def inp():
        if not nostdin:
            while True:
                d = os.read(0, 65536)
                if not d: break
                send(s, lock, 0, d)
        send(s, lock, 0, b"")
    threading.Thread(target=inp, daemon=True).start()
    while True:
        h = recvall(s, 5)
        if h is None: sys.exit(255)
        t, n = struct.unpack("!BI", h); d = recvall(s, n) if n else b""
        if t == 1: os.write(1, d)
        elif t == 2: os.write(2, d)
        elif t == 3: sys.exit(int(d))
if __name__ == "__main__":
    if sys.argv[1:2] == ["--serve"]: serve()
    else: client(sys.argv[1:])
