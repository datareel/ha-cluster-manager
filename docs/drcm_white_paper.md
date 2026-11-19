# DataReel Cluster Manager (DRCM): design and security white paper

**Release:** 1.49 (November 2026). Items marked **1.49** are new in this
release.
**Audience:** system administrators, architects and security reviewers
deciding whether to run services on DRCM clusters. The source code is
published under the GNU General Public License, so everything here can be
checked against it. The commands and every setting are in the
[administrator guide](https://datareel.com/drcm/admin_guide.html).

## 1. Summary

DRCM keeps services running when a Linux server fails or is taken down for
patching. Two or more nodes, servers or workstations, watch each other with
authenticated keep alive messages. When a node stops answering, or is put
in standby for maintenance, its peers take over its resources: floating IP
addresses, system services, applications, file systems and cron jobs. A
cluster can sit in one data center, span several sites, run entirely in a
cloud such as AWS, or combine on-premises nodes with cloud nodes.

DRCM is one small C++ program, `drcm_server`, with plain text configuration
and shell resource scripts. It has run in production for ten years, on RHEL
6, RHEL 7, RHEL 8, RHEL 9 and RHEL 10; current releases support RHEL 8, 9
and 10.

## 2. The problem it solves

- **Unplanned failures:** a host, a VM, a disk or a network path fails, and
  the services on it stop until someone notices and moves them.
- **Planned maintenance:** patching and reboots take services down unless
  something moves them first and moves them back afterwards.
- **Sites and clouds:** a second node in another building, site or cloud
  region protects against the loss of a whole location, but only if
  failover works across routed and internet links, not just a shared LAN.
- **Split brain:** when the link between two nodes breaks, each may think
  the other is dead and both start the same service. A cluster manager has
  to prevent that, not just detect failures.

## 3. Architecture

[[figure architecture]]

- **Peers, no master.** Every node runs the same `drcm_server` binary with
  the same `/etc/drcm` directory. Resources are spread across the nodes,
  and each resource names its primary node and its backup nodes in order.
- **Threads.** A UDP server thread answers keep alives and client commands;
  in TCP mode a TCP + TLS server thread serves the same messages. One
  thread per resource type (crontabs, IP addresses, services, applications,
  file systems) starts, stops and watches its resources on its own check
  interval. A log thread and a dedicated signal thread run alongside.
- **Keep alives.** Each node probes every other active node. After
  `dead_node_count` failed probes in a row, the node is declared dead and
  its backups take over its resources, staggered by their position in the
  configuration so two backups do not start the same resource at once.
- **Resource scripts.** Shell scripts in `/etc/drcm/resources` do the start,
  stop and watch work: floating IPs with NetworkManager (IPv4 and IPv6),
  AWS Elastic IPs and route-table VIPs, NFS and CIFS mounts, system
  services, cron jobs. Sites add their own with the same arguments.
- **Client commands.** `drcm_server --client` shows the cluster
  (`cm_stat`, `rstats`, `ping`, `printcfg`) and puts nodes in standby.
  Client commands are authenticated cluster messages like the keep alives.

## 4. Failover, failback and standby

- **Failover.** When a node is declared dead, each of its resources starts
  on its first live backup. When the node comes back, it takes its own
  resources back (failback) and the backup stops its copies.
- **Keeping resources up while DRCM stops.** `keep_services`,
  `keep_applications` and `keep_filesystems` leave a node's own resources
  running when DRCM itself is stopped or restarted, for example during a
  DRCM upgrade.
- **Standby (1.43 and later).** `drcm_server --client --command=standby`
  moves a node's resources to its backups while DRCM keeps running, for
  patching or to test that applications fail over. It refuses, and
  changes nothing, if no live peer can take the resources (unless
  `--force`). `unstandby` returns the node to service and waits for the
  peers to stop their copies first, so a resource never runs twice.
- **Timed standby (1.46).** `--time=2h` ends the standby by itself, even if
  nobody is there to run `unstandby`.
- **Remote standby (1.47).** `-n"node"` puts another node in standby from
  this one, for example from a cloud node when the main site is
  unattended. It is off unless the target sets `allow_remote_standby = 1`,
  and the target accepts it only from a cluster node identified by the
  cluster key and, in TCP mode, by its pinned TLS certificate.

## 5. Run local, fail over to the cloud

[[figure hybrid]]

A common layout keeps the primary node in the organization's own data
center and a backup node in a cloud such as AWS:

- **Transport.** The UDP transport suits nodes on one network. Across
  routed or internet links, the TCP transport carries every cluster
  message inside mutually authenticated TLS on one TCP port (default
  53897). An SSH tunnel works too.
- **Floating addresses in AWS.** An interface alias does not move between
  EC2 instances, so `aws_ipv4addr.sh` moves the address through the EC2
  API: an Elastic IP (associated with the active instance) or a
  route-table VIP (the VIP's /32 route points at the active instance).
- **Data.** 2-way file replication keeps data directories in step between
  nodes with no shared storage, over SSH and rsync, and an optional third
  copy goes to an off-site host. A primary that comes back after a
  failover does not start its scheduled jobs until the data has been
  synchronized back (`crontab_fs_guard.sh`).
- **Split brain across sites** is the main risk of this layout; section 6
  covers the protections.

## 6. Split brain protection

DRCM has three independent protections. Each is optional and each is a
plain setting, so a site uses the ones that fit its network.

- **Witness quorum (1.42).** With `quorum_required = 1`, a node takes over a
  dead peer's resources only if it can reach a third DRCM endpoint, the
  witness, with an authenticated message. A node that cannot reach the
  witness is probably the isolated one and stands down. With no witness
  configured, quorum fails closed.
- **Self-isolation (1.43).** `isolation_check` names a script that tells
  whether this node can still reach the outside world (the supplied
  `internet_check.sh` tests public addresses). When every peer stops
  answering and the check also fails, the node stops its own floating IPs,
  services, applications and cron jobs and takes over nothing. Tested on a
  workstation and AWS cluster: with the workstation's internet link down,
  it stood down its resources 25 seconds after the link was lost, before
  the AWS node took over.
- **Takeover check (1.43).** `takeover_check` runs a script before every
  takeover; a non-zero exit stops it. The supplied `drsm_report_check.sh`
  asks a DataReel System Monitor dashboard when the "dead" peer last
  reported: a recent report means only the cluster link is down, so the
  takeover is refused.

## 7. Security design

[[figure layers]]

### 7.1 What is protected, and from whom

The cluster messages decide where services run. An attacker who could
forge them could stop services or start them on the wrong node. DRCM
assumes an attacker who can send packets to the cluster port, record and
replay traffic, and, across the internet, sit on the path between nodes.
It does not defend against an attacker who already has root on a cluster
node: root can read the cluster key and run any command.

### 7.2 Authenticated messages (1.42 and later)

- **Cluster key.** Every node holds the same `/etc/drcm/.auth/authkey`: 2048
  random bytes, readable by root only (folder mode 700, file mode 600). The
  server checks the permissions at startup and warns if other users can
  read the key.
- **Every message is signed.** Each keep alive, reply and client command is
  a version 2 frame: a 76-byte header (magic, version, command, flags,
  payload length, timestamp, sequence number and a 16-byte random nonce)
  plus the payload, with an HMAC-SHA256 over the whole frame keyed with the
  cluster key. The HMAC is checked in constant time before any field is
  trusted, so a forged or changed message is rejected.
- **Replay protection.** The receiver remembers the last 256 nonces of each
  peer and rejects an exact replay without needing synchronized clocks. On
  a TCP connection the sequence number must also increase. An optional
  `replay_window_secs` also rejects old timestamps when clocks are
  synchronized.
- **Bounded input.** Payloads are capped at 65,507 bytes and statistics
  replies at 64 KB, so a length field cannot drive a large allocation.
  The UDP protocol was fuzzed with 2,000 malformed packets under
  AddressSanitizer and UBSan without a fault.

### 7.3 TLS for the TCP transport

- **Mutual authentication.** Both ends present a certificate signed by the
  cluster's own certificate authority and verify the other end against
  it; the handshake fails closed. Plain TCP, a client without a
  certificate and a certificate from another CA are refused at the
  handshake.
- **Pinning.** `tls_peer_fingerprint` pins a node's certificate by its
  SHA-256 fingerprint; any other certificate is rejected.
- **Two layers.** TLS adds encryption and certificate checks; it does not
  replace the frame HMAC. A client with a valid cluster certificate but
  without the cluster key still cannot forge a command.
- **Versions.** TLS 1.2 is the floor; `tls_min_version = 1.3` raises it.

### 7.4 Running commands safely

- Application start, stop and check commands run as the configured user
  through `su` or `sudo`, with the arguments shell quoted.
- Process lock files are mode 644, process IDs are matched exactly, and a
  lock owner can only stop its own child processes.
- The CIFS password goes in a private credentials file, never on a command
  line. SSH and rsync calls use `StrictHostKeyChecking=accept-new`, which
  refuses a host key that changes.
- Signals are handled in a dedicated thread, not in a signal handler.
- The server is built with stack protector, `_FORTIFY_SOURCE=2`, position
  independent code and full RELRO.

## 8. Post-quantum readiness

- **Not affected by quantum computers:** the message HMAC-SHA256 with the
  2048-byte shared cluster key. It is symmetric, so Shor's algorithm does
  not apply, and Grover's algorithm still leaves far more than 128 bits of
  strength.
- **TLS key exchange.** A recorded TLS session could be decrypted later by
  a quantum computer if its key exchange is classic (X25519 or ECDHE).
  OpenSSL 3.5 adds the hybrid key exchange X25519MLKEM768 (ML-KEM-768, NIST
  FIPS 203, combined with X25519) and prefers it in TLS 1.3. The RHEL 9 and
  RHEL 10 RPMs use the system OpenSSL 3.5, so TCP clusters of those nodes
  negotiate it with TLS 1.3.
- **1.49:**
  - RHEL 8 gets a second package, `drcm_server-openssl35`, with OpenSSL
    3.5 built in, so RHEL 8 nodes can use the hybrid key exchange too.
  - A `tls_groups` setting (default `X25519MLKEM768:X25519`) and a strict
    `tls_pq_only` mode, which allows only the hybrid group and requires
    TLS 1.3. `--check-config` refuses a group the linked OpenSSL does not
    have.
  - The log shows each peer's TLS version and key exchange, so the
    administrator can see that the hybrid group is in use, and
    `drcm_server --version` prints the linked OpenSSL.
  - Recommended once every node runs 1.49: `tls_min_version = 1.3`.
- **FIPS mode.** On a host in FIPS mode DRCM sets no group list and the
  system crypto policy picks FIPS-approved groups. The validated FIPS
  providers have no ML-KEM yet, so FIPS mode means a classic key exchange
  for now (**1.49**). The static OpenSSL of `drcm_server-openssl35` does
  not read the system crypto policy, so in FIPS mode that build limits the
  key exchange to P-256, P-384 and P-521 itself and logs a warning; its
  OpenSSL is still not a validated module. OpenSSL's 3.1.2 FIPS provider (CMVP certificate
  #4985) is validated and works with OpenSSL 3.5; a validated provider
  with ML-KEM would allow both.
- **Certificates.** Node certificates (RSA or ECDSA) authenticate live
  handshakes; recorded traffic does not help forge them later.
  Post-quantum certificates (ML-DSA) are a possible later option.
- **UDP transport.** UDP messages are authenticated but not encrypted, with
  or without quantum computers. Use the TCP transport where cluster
  traffic must stay confidential.

## 9. Platforms and packaging

- **Supported:** RHEL 10 and RHEL 9, and RHEL 8 (best effort), and
  compatible distributions. RHEL 6 and 7 are no longer supported; 1.37 was
  their last release.
- **Packages:** RPMs for RHEL 8, 9 and 10 and the source code, each with a
  SHA-256 checksum, on the [downloads page](https://datareel.com/downloads/drcm_downloads.php).
  The RPM installs a native systemd unit.
- **OpenSSL per platform:** RHEL 10 and RHEL 9 use the system OpenSSL 3.5.
  RHEL 8 has two packages from **1.49**:
  - `drcm_server` (**recommended**) links RHEL 8's system OpenSSL 1.1.1,
    which Red Hat has FIPS-validated; classic TLS key exchange. `dnf
    upgrade` from 1.37 or 1.48 stays on this package, its OpenSSL fixes
    come with `dnf update`, and it is the one for hosts in FIPS mode.
  - `drcm_server-openssl35` (optional) has OpenSSL 3.5 LTS built in
    (static, from the checksum-verified upstream release) and the
    post-quantum key exchange. It is meant for hosts not in FIPS mode that
    run the TCP + TLS transport across networks the site does not control;
    with the UDP transport it adds nothing. DataReel re-releases it for
    OpenSSL 3.5 security fixes.
  - `dnf install --allowerasing` with the other RPM (or `dnf swap` from a
    repository) moves a node between the two while DRCM is stopped,
    keeping the configuration, keys and service state.
- **Networking:** NetworkManager for floating IPs on RHEL 8 and later, and
  firewalld for the cluster port. Floating IPs can be IPv4 or IPv6; the
  cluster traffic between nodes is IPv4.

## 10. Operations

- **Install:** the RPM on every node, the same `/etc/drcm` everywhere, one
  cluster key copied to every node.
- **Check before start:** `drcm_server --check-config` reports every
  configuration error, missing script and missing TLS file before the
  server runs.
- **Watch:** `cm_stat` shows every node, its state and where each resource
  runs; logs are in `/var/log/drcm`. The DataReel System Monitor has a
  cluster plug-in that shows DRCM clusters on its dashboard.
- **Upgrade:** releases 1.42 and later talk to each other, so those
  clusters can be upgraded one node at a time with standby. Release 1.42
  changed the cluster protocol, so a cluster on 1.41 or older (for example
  1.37) is upgraded with every node stopped, then upgraded, then started.
  The read-only pre-flight check (`tools/drcm_preflight.sh`) tells, for
  each node, what an upgrade will keep and replace.

## 11. AI-assisted install, upgrade and support

DRCM includes an AI-assisted guide, `AGENTS.md` (with `GEMINI.md` and
`CLAUDE.md`), that lets the site's own approved AI desktop or command line
tools help its administrators install, set up, upgrade and troubleshoot
DRCM.

- **Before you use any AI assistance, review all of your agency's or
  company's AI usage policies, and get formal written approval from your
  management team in the form of a business use case and justification.**
- **Use only approved enterprise AI models.** An AI agent may process
  potentially sensitive data such as host names, configuration files and
  logs. Use only enterprise AI models that guarantee your internal
  information will not be used to train public models. Public or free AI
  tools, open source AI models and self-built AI models may expose your
  information, depending on how they are hosted, configured and licensed;
  use them only after a comprehensive review of the risks.
- **Human in the loop, never autonomous.** The AI tool explains each step
  and proposes the exact command; administrators run it or approve it, one
  step and one node at a time. The guide works fully in advisory mode,
  where the AI tool runs no commands at all.
- The entire risk of AI-assisted use rests with the user. Any mention of a
  specific AI tool is a reference only, not an endorsement.

## 12. Limits, stated plainly

- **Root on a node owns the cluster.** The cluster key is a file readable
  by root; whoever has it can forge any cluster message. Protect root
  access, and replace the key on every node if it may have leaked.
- **UDP is not encrypted.** Use the TCP transport where cluster traffic
  must stay confidential.
- **No hardware fencing.** DRCM does not power off a failed node through a
  management controller or a power switch. Split brain protection relies
  on the witness, the isolation check and the takeover check (section 6);
  a two-node cluster without any of them can run a service on both nodes
  while the link between them is down.
- **Failover is not instant.** A dead node is declared after
  `dead_node_count` missed keep alives, then resources start in order;
  clients see the outage for that time. Standby moves resources ahead of
  planned work instead.
- **Applications must tolerate a restart elsewhere.** DRCM moves the
  address, the data and the service; it does not replicate memory or open
  connections.
- **Replay window needs clocks.** `replay_window_secs` assumes
  synchronized clocks; leave it at 0 without chrony.
- **RHEL 8 is best effort.** Its post-quantum package carries its own
  OpenSSL, so its OpenSSL fixes come with DRCM releases, not with `dnf
  update` of the system OpenSSL.
- **FIPS mode and post-quantum TLS do not combine yet:** the validated
  FIPS providers have no ML-KEM.

## 13. Licensing

DRCM is free software under the GNU General Public License version 3. The
bundled DataReel library files it uses are under the GNU Lesser General
Public License version 3. Both are provided as is, without warranty; see
the license files in the source code and the site's terms of use.

## 14. References

- Administrator guide: [datareel.com/drcm/admin_guide.html](https://datareel.com/drcm/admin_guide.html) (also plain text)
- AI-assisted install, upgrade and support guide:
  [datareel.com/drcm/ai_assisted_guide.php](https://datareel.com/drcm/ai_assisted_guide.php) and `AGENTS.md`
- Release notes: `CHANGELOG.md` in the source code
- Product page: [datareel.com/info_drcm.php](https://datareel.com/info_drcm.php)
- Downloads: [datareel.com/downloads/drcm_downloads.php](https://datareel.com/downloads/drcm_downloads.php)

## 15. Reporting a security issue

Please report a suspected vulnerability privately from the
[contact page](https://datareel.com/contact.php), with the DRCM version, the platform and the
steps to reproduce it. Do not post it publicly until a fixed release is
available.
