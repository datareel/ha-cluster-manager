#!/usr/bin/env python3
"""Make docs/drcm_white_paper.html and docs/drcm_white_paper.txt from
docs/drcm_white_paper.md (the source; edit only that file).

  python3 tools/make_white_paper.py

The HTML is self-contained and uses the styles, theme toggle and layout of
docs/drcm.html (read from that file, so the two look alike). Lines
"[[figure NAME]]" in the source become SVG figures in the HTML and text
diagrams in the plain text copy. The website publishes byte copies of both
files and a page made from the HTML. Needs python3-markdown.
"""
import html
import os
import re
import sys

import markdown

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
DOCS = os.path.join(ROOT, 'docs')
SRC = os.path.join(DOCS, 'drcm_white_paper.md')
GUIDE = os.path.join(DOCS, 'drcm.html')

md = open(SRC, encoding='utf-8').read()
guide = open(GUIDE, encoding='utf-8').read()

# ------------------------------------------------------------------ figures
SVG = {
'architecture': ('Two or more DRCM nodes exchange authenticated keep alives; each node runs resource threads that start and stop resources with scripts', '''
<svg viewBox="0 0 720 250" width="720" xmlns="http://www.w3.org/2000/svg">
  <rect class="boxa" x="20" y="30" width="250" height="190" rx="10"/>
  <text x="38" y="56" font-weight="600">cmnode1 (primary for web)</text>
  <text class="muted" x="38" y="80">drcm_server</text>
  <text class="muted" x="38" y="100">UDP or TCP + TLS server thread</text>
  <text class="muted" x="38" y="120">resource threads: IPs, services,</text>
  <text class="muted" x="38" y="138">applications, file systems, crons</text>
  <text class="muted" x="38" y="162">/etc/drcm/resources/*.sh</text>
  <text class="muted" x="38" y="182">/etc/drcm/cm.cfg (same on all)</text>
  <text class="muted" x="38" y="202">/etc/drcm/.auth/authkey (root only)</text>
  <rect class="box" x="450" y="30" width="250" height="190" rx="10"/>
  <text x="468" y="56" font-weight="600">cmnode2 (backup for web)</text>
  <text class="muted" x="468" y="80">drcm_server</text>
  <text class="muted" x="468" y="100">same binary, same /etc/drcm</text>
  <text class="muted" x="468" y="120">takes over web when cmnode1</text>
  <text class="muted" x="468" y="138">misses dead_node_count keep alives</text>
  <text class="muted" x="468" y="162">or goes into standby</text>
  <path class="line" d="M270 95 H450"/>
  <path class="line" d="M450 125 H270"/>
  <text x="292" y="87">keep alives, commands</text>
  <text class="muted" x="292" y="145">signed with HMAC-SHA256</text>
  <text class="muted" x="20" y="18">clients use the floating IP, which moves to the node that runs the resource</text>
  <rect class="box" x="290" y="190" width="140" height="34" rx="8"/>
  <text x="309" y="212">witness (optional)</text>
  <path class="line dash" d="M270 207 H290"/>
  <path class="line dash" d="M450 207 H430"/>
</svg>'''),
'hybrid': ('A primary node in the organization\'s data center and a backup node in a cloud region, joined by TCP and TLS over the internet, with data replication and an optional witness in a third place', '''
<svg viewBox="0 0 720 230" width="720" xmlns="http://www.w3.org/2000/svg">
  <rect class="box" x="10" y="20" width="270" height="180" rx="12"/>
  <text x="26" y="44" font-weight="600">Your data center</text>
  <rect class="boxa" x="30" y="60" width="230" height="120" rx="10"/>
  <text x="46" y="86" font-weight="600">primary node</text>
  <text class="muted" x="46" y="108">floating IP (NetworkManager)</text>
  <text class="muted" x="46" y="128">services, applications, crons</text>
  <text class="muted" x="46" y="148">data directories</text>
  <rect class="box" x="440" y="20" width="270" height="180" rx="12"/>
  <text x="456" y="44" font-weight="600">Cloud region (for example AWS)</text>
  <rect class="boxa" x="460" y="60" width="230" height="120" rx="10"/>
  <text x="476" y="86" font-weight="600">backup node</text>
  <text class="muted" x="476" y="108">Elastic IP or route-table VIP</text>
  <text class="muted" x="476" y="128">starts the services on failover</text>
  <text class="muted" x="476" y="148">replicated data</text>
  <path class="line" d="M260 95 H460"/>
  <text x="290" y="88">TCP + mutual TLS</text>
  <path class="line dash" d="M260 140 H460"/>
  <text class="muted" x="290" y="134">rsync over SSH (data)</text>
  <rect class="box" x="290" y="182" width="140" height="34" rx="8"/>
  <text x="309" y="204">witness (third site)</text>
</svg>'''),
'layers': ('Every cluster message is a signed version 2 frame; in TCP mode the frame travels inside mutually authenticated TLS', '''
<svg viewBox="0 0 720 200" width="720" xmlns="http://www.w3.org/2000/svg">
  <rect class="box" x="20" y="20" width="680" height="160" rx="12"/>
  <text x="38" y="44" font-weight="600">TLS 1.2+ (TCP transport): mutual certificates from the cluster CA, optional pinning</text>
  <text class="muted" x="38" y="64">key exchange X25519MLKEM768 (post-quantum hybrid) with OpenSSL 3.5 and TLS 1.3</text>
  <rect class="boxa" x="40" y="80" width="640" height="84" rx="10"/>
  <text x="58" y="104" font-weight="600">version 2 frame (UDP and TCP)</text>
  <text class="muted" x="58" y="126">76-byte header: command, length, timestamp, sequence, 16-byte nonce</text>
  <text class="muted" x="58" y="146">payload | HMAC-SHA256 over the whole frame, keyed with the 2048-byte cluster key</text>
</svg>'''),
}
ASCII = {
'architecture': '''
    clients -> floating IP (moves to the node that runs the resource)

    +---------------------------+   keep alives,    +---------------------------+
    | cmnode1 (primary for web) |   commands        | cmnode2 (backup for web)  |
    | drcm_server               | <---------------> | drcm_server               |
    | resource threads + scripts|  HMAC-SHA256      | takes over web when       |
    | /etc/drcm (same on all)   |  signed frames    | cmnode1 is dead or in     |
    | .auth/authkey (root only) |                   | standby                   |
    +---------------------------+                   +---------------------------+
                  \\                                             /
                   +------------ witness (optional) -----------+
''',
'hybrid': '''
    Your data center                          Cloud region (for example AWS)
    +-------------------------+   TCP + mutual TLS   +-------------------------+
    | primary node            | <------------------> | backup node             |
    | floating IP (nmcli)     |                      | Elastic IP or route VIP |
    | services, crons, data   | - - rsync over SSH - | replicated data         |
    +-------------------------+                      +-------------------------+
                         \\                             /
                          +---- witness (third site) --+
''',
'layers': '''
    +----------------------------------------------------------------------+
    | TLS 1.2+ (TCP transport): mutual certificates, optional pinning;     |
    | key exchange X25519MLKEM768 with OpenSSL 3.5 and TLS 1.3             |
    |  +----------------------------------------------------------------+  |
    |  | version 2 frame (UDP and TCP): 76-byte header (command, length, |  |
    |  | timestamp, sequence, nonce) + payload + HMAC-SHA256 keyed with  |  |
    |  | the 2048-byte cluster key                                       |  |
    |  +----------------------------------------------------------------+  |
    +----------------------------------------------------------------------+
''',
}
FIG_RE = re.compile(r'^\[\[figure (\w+)\]\]$', re.M)
for name in FIG_RE.findall(md):
    if name not in SVG or name not in ASCII:
        sys.exit('unknown figure: ' + name)

# --------------------------------------------------------------------- HTML
title_m = re.match(r'# (.+)\n', md)
title = title_m.group(1)
body_md = md[title_m.end():]
body_md = FIG_RE.sub(lambda m: '\n<!--FIG:%s-->\n' % m.group(1), body_md)
body = markdown.markdown(body_md, extensions=['tables', 'fenced_code'], output_format='html5')
if '<?' in body:
    sys.exit('the source contains "<?", which would start PHP code in the website page')
for name, (label, svg) in SVG.items():
    body = body.replace('<!--FIG:%s-->' % name,
                        '<div class="diagram" role="img" aria-label="%s">%s\n</div>' % (html.escape(label), svg))

# Split into the lead (before the first h2) and numbered sections
parts = re.split(r'(?=<h2>)', body)
lead, sections = parts[0], parts[1:]
nav, out_sections = [], []
for sec in sections:
    h = re.match(r'<h2>(\d+)\. (.+?)</h2>', sec)
    if not h:
        sys.exit('every ## heading must start with a number: ' + sec[:60])
    num, text = h.group(1), h.group(2)
    sid = 'sec' + num
    nav.append('    <li><a href="#%s">%s</a></li>' % (sid, re.sub(r'<[^>]+>', '', text)))
    out_sections.append('<section id="%s">\n%s</section>\n' % (sid, sec))

style = guide[guide.index('<style>'):guide.index('</style>') + len('</style>')]
script = guide[guide.rindex('<script>'):guide.rindex('</script>') + len('</script>')]
fonts = '\n'.join(l for l in guide.splitlines() if 'fonts.g' in l)
version = re.search(r'\*\*Release:\*\* ([0-9.]+)', md).group(1)
desc = ('DataReel Cluster Manager (DRCM) design and security white paper: architecture, failover and standby, '
        'hybrid local and cloud clusters, split brain protection, authenticated messages, TLS, post-quantum '
        'readiness, platforms, operations and limits.')

page = f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>DRCM White Paper</title>
<meta name="description" content="{html.escape(desc)}">
{fonts}
{style}
</head>
<body>
<!-- Made by tools/make_white_paper.py from docs/drcm_white_paper.md; edit the .md file. -->
<div class="topbar">
  <button class="btn" id="navToggle" type="button" aria-controls="rail" aria-expanded="false">&#9776; Contents</button>
  <div class="brand">DRCM <span>White Paper</span></div>
  <div class="spacer"></div>
  <button class="btn" id="themeToggle" type="button" aria-label="Toggle light or dark theme"><span id="themeLabel">Theme</span></button>
</div>

<div class="layout">
<nav class="rail" id="rail" aria-label="Sections">
  <h2>Contents</h2>
  <ol>
{chr(10).join(nav)}
  </ol>
</nav>

<main>
<header class="hero">
  <h1>{html.escape(title)}</h1>
  <p>How DRCM keeps Linux services running through failures and maintenance, on premises, in the cloud or both, and how it protects the cluster.</p>
  <div class="meta">
    <span class="pill">Release {version}</span>
    <span class="pill">RHEL 10 &middot; 9 &middot; 8</span>
    <span class="pill">Plain text copy: drcm_white_paper.txt</span>
  </div>
</header>
<section id="intro">
{lead}</section>
{''.join(out_sections)}<footer>DataReel Cluster Manager {version} white paper &middot; Copyright &copy; DataReel Software Development &middot; GNU General Public License.</footer>
</main>
</div>

{script}
</body>
</html>
'''
open(os.path.join(DOCS, 'drcm_white_paper.html'), 'w', encoding='utf-8').write(page)

# ---------------------------------------------------------------- plain text
txt = md
txt = FIG_RE.sub(lambda m: ASCII[m.group(1)].strip('\n'), txt)
txt = re.sub(r'\[([^\]]+)\]\((https?://[^)]+)\)', lambda m: m.group(1) if m.group(1) in m.group(2) else '%s (%s)' % (m.group(1), m.group(2)), txt)
txt = txt.replace('**', '').replace('`', '')
def head(m, ch):
    t = m.group(1)
    return t + '\n' + ch * len(t)
txt = re.sub(r'^# (.+)$', lambda m: head(m, '='), txt, flags=re.M)
txt = re.sub(r'^## (.+)$', lambda m: head(m, '-'), txt, flags=re.M)
txt = re.sub(r'^### (.+)$', lambda m: head(m, '.'), txt, flags=re.M)
open(os.path.join(DOCS, 'drcm_white_paper.txt'), 'w', encoding='utf-8').write(txt)
print('wrote docs/drcm_white_paper.html and docs/drcm_white_paper.txt (%d sections)' % len(sections))
