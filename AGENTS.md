# DRCM (DataReel Cluster Manager): AI-assisted install, upgrade and support

This file is for AI-assisted work on DRCM: it tells an AI agent (Gemini
CLI, Claude Code, GitHub Copilot, Codex and others) how to assist a
site's own system administrators to install DRCM, set up a cluster,
upgrade old releases such as 1.37 to the current release, 1.49, and
troubleshoot. The agent assists; it does not replace the administrators
or DataReel support, and it never acts autonomously (section 0). The
administrators review and approve every step, and problems the agent
cannot solve go to DataReel (section 7.4).
`GEMINI.md` and `CLAUDE.md` in this folder only import this file.

The full manual is `docs/drcm.txt` (also `docs/drcm.html` and
https://datareel.com/drcm/admin_guide.html). This file points to its
sections instead of repeating them. When this file and the manual
disagree, the manual and the code win: say so to the person you work for.

## Before you use AI assistance

**Review all of your agency's or company's AI usage policies, and get formal
written approval from your management team, in the form of a business use
case and justification, before you use any AI assistance with DRCM.** AI
desktops and command line tools may be used with this guide only in strict
compliance with those policies and that approval.

- **Use only approved enterprise AI models.** An AI agent working on a
  cluster may process potentially sensitive data: host names, addresses,
  configuration files, logs and command output. Use only your agency's or
  company's enterprise AI models that have built-in safeguards against
  disclosing information and that guarantee your internal information will
  not be used to train public models.
- **Warning: public or free AI tools, open source AI models and self-built
  AI models** may expose your information to public learning models or to
  other parties, depending on how the model is hosted, configured and
  licensed. Use them only after a comprehensive review of what information
  might be exposed and what the potential risks are.
- The entire risk of AI-assisted use rests with the user. DataReel cannot
  be held accountable for actions taken, commands run or other outcomes of
  AI assistance (see https://datareel.com/terms.php).
- **No endorsement.** Any mention of a specific AI tool, model or product
  in this guide, such as Gemini, Gemini CLI, Claude Code or GitHub Copilot,
  is a reference only. It is not an endorsement or a recommendation to use
  that product. Product names are trademarks of their respective owners.

**For the agent:** at the start of a session, ask the person to confirm
that this AI-assisted use is approved under their organization's AI usage
policy and that you are an approved enterprise AI model. If they cannot
confirm it, stop and do not ask for or read any cluster data.

## 0. Human in the loop: the agent never acts on its own

AI-assisted means the agent assists a person; it never acts
autonomously. Every change to a cluster node is made by an administrator
or explicitly approved by one, one step at a time.

- **Advisory mode is the default.** The agent explains the next step and
  prints the exact command and the node it is for. The administrator runs
  it and pastes the output back. Use this mode unless the organization
  allows the agent to run tools.
- **If tool execution is allowed,** each command still needs its own
  explicit approval before it runs. Never use auto-approve modes: no
  Gemini CLI `--yolo` or auto-accept, no Claude Code permission bypass
  (`--dangerously-skip-permissions`, bypass mode), no auto-run in other
  agents.
- **No unattended work:** no scheduled, background, batch or scripted
  runs of changing commands, no loops over nodes, and no changes across
  nodes over SSH loops, `pdsh`, Ansible or similar. One node per approval.
- **Read-only diagnostics first.** The agent may propose read-only checks
  (section 7.1, `tools/drcm_preflight.sh`) before anything else; they are
  shown and approved the same way.

**Works with strict AI policies.** These files contain no code that runs
by itself: `AGENTS.md`, `GEMINI.md` and `CLAUDE.md` are text, and
`tools/drcm_preflight.sh` is a read-only script that the administrator
runs. Everything in this guide works in advisory mode, with no tool
execution by the agent.

## 1. Rules for agents (read these first)

DRCM moves floating IPs, services, file systems and cron jobs between
production servers. A wrong step causes an outage or a split brain (two
nodes running the same service). Follow these rules on every task:

1. **One node at a time.** Never run a changing command on more than one
   node in one step, and never in a loop over nodes, unless the person has
   confirmed that exact step for those nodes.
2. **Show, then the person runs or approves it.** Before any command that
   changes a node (dnf, rpm, systemctl start/stop/restart, edits under
   /etc, firewall-cmd, nmcli), print the command and the node name. In
   advisory mode the administrator runs it; otherwise wait for an explicit
   yes for that one command (section 0).
3. **Back up before changing.** Copy `/etc/drcm`, `/etc/sysconfig/drcm_server`
   and any unit file you will touch into a dated backup folder first (see
   5.3). Never delete; move aside.
4. **Stop on any failed check.** If a check fails or the output is not what
   this guide says to expect, stop and report. Do not improvise a fix on a
   production cluster.
5. **Never touch the auth keys' contents.** Do not print, copy over the
   network, regenerate or "fix" `/etc/drcm/.auth/authkey`. Compare nodes
   with `authkey.sha1` only. A new key on one node splits the cluster.
6. **Never weaken the safety settings silently.** Do not turn off firewalld,
   SELinux, `isolation_check`, `takeover_check`, quorum or TLS, and do not
   set `StrictHostKeyChecking=no`, to make something work. Report instead.
7. **Read-only first.** Start every task with the read-only checks:
   `tools/drcm_preflight.sh`, `drcm_server --client --command=cm_stat`,
   `--check-config`, `rpm -q`, `systemctl status`, the log in
   `/var/log/drcm/`.
8. **No secrets or site data in files you write** (host names, addresses,
   keys, passwords), unless the person asks for that file on their own
   systems.
9. **Keep a log.** List each command you ran, on which node, and its result,
   and give it to the person at the end.

## 2. What DRCM is

DRCM builds high availability Linux clusters of 2 or more nodes (servers or
workstations, on premises, in the cloud, or both). Each node runs
`drcm_server` as a systemd service. Nodes exchange authenticated keep alive
messages; when a node stops answering, its peers take over its resources
(floating IPs, services, applications, file systems, cron jobs) in the order
set in the config file. A node can be put in standby for maintenance
(`--command=standby`, 1.43 and later).

| Item | Location (1.49) |
| --- | --- |
| Server binary | `/usr/sbin/drcm_server` |
| Config file | `/etc/drcm/cm.cfg` (override with `CFGFILE` in `/etc/sysconfig/drcm_server`) |
| Auth keys | `/etc/drcm/.auth/authkey` (2048 random bytes) and `authkey.sha1` (40 hex characters); folder mode 700, files 600; identical on every node |
| Resource scripts | `/etc/drcm/resources/*.sh` (floating IPs: `ipv4addr_nmcli.sh` on RHEL 8 and later) |
| Helper scripts | `/etc/drcm/utils/`, `/etc/drcm/file_system_sync/`, `/etc/drcm/my_cluster_conf/` |
| systemd unit | `/usr/lib/systemd/system/drcm_server.service` (Type=simple, KillMode=process) |
| Extra arguments | `ARGS=` in `/etc/sysconfig/drcm_server` |
| Logs | `/var/log/drcm/drcm.log` and the resource logs next to it; `journalctl -u drcm_server` |
| State | `/var/lib/drcm/` (standby file, file system sync flags) |
| Port | `udpport` / `tcpport` in cm.cfg (examples use 53897) |

Read-only status commands (run on a node):

```
drcm_server --version
drcm_server --client --command=cm_stat     # this node's view: nodes, resources, owners
drcm_server --client --command=rstats      # resource stats from every node
drcm_server --check-config --config-file=/etc/drcm/cm.cfg
```

## 3. Repository layout and building (development work)

| Path | Contents |
| --- | --- |
| `drcm_server/` | the server and client (C++); `make` builds `drcm_server` |
| `include/`, `src/` | bundled DataReel library files (6.4.1); resync with `build/sync_datareel.sh` |
| `etc/` | files installed under `/etc/drcm` (example configs, resource and helper scripts) |
| `systemd_init/` | the systemd unit |
| `rpm_builder/` | RPM specs (`drcm_rhel8/9/10.spec`) and `make_rhelN_rpm.sh` |
| `test_apps/standby_test/` | podman cluster tests (`setup.sh`, `run_tests.sh`, `TRANSPORT=tcp`) |
| `tools/` | `drcm_preflight.sh` (upgrade checks), `migrate_cfg.py` (TCP/TLS and quorum settings), `drcm_gui.py` |
| `docs/` | administrator guide (`drcm.txt`, `drcm.html`) |

Build: `cd drcm_server && make` (needs gcc-c++, make, openssl-devel).
RPMs: build inside a UBI 8, 9 or 10 container with `cd rpm_builder &&
bash make_rpm_package.sh rhel8` (or rhel9, rhel10). Run the podman suites
one at a time: they share container names. Every release bumps
`version.txt`, `VersionString` in `drcm_server/m_help.cpp`, `Version:` and
`%changelog` in the three specs, the man pages, README.txt, the guide and
CHANGELOG.md.

## 4. New install on RHEL 8, 9 or 10

Manual: sections 3 and 4 of `docs/drcm.txt`.

1. Download the RPM for the OS (`drcm_server-1.49-1.el8.x86_64.rpm`, el9 or
   el10) and its `.sha256sum` from https://datareel.com/downloads/drcm_downloads.php.
   Check it: `sha256sum -c drcm_server-1.49-1.el8.x86_64.rpm.sha256sum`.
   Stop if it fails.
2. `dnf -y install ./drcm_server-1.49-1.el8.x86_64.rpm` on each node (one
   node at a time, rule 1). RHEL 9 and 10 have one package. RHEL 8 has
   two; the person chooses:
   - `drcm_server-1.49-1.el8.x86_64.rpm`: RHEL 8's system OpenSSL 1.1.1,
     FIPS-validated, classic TLS. Required on hosts in FIPS mode
     (`fips-mode-setup --check`).
   - `drcm_server-openssl35-1.49-1.el8.x86_64.rpm`: OpenSSL 3.5 built in,
     post-quantum TLS key exchange, nothing extra to install. Not for FIPS
     mode.
3. Make the auth keys on ONE node, then copy the two files to the others
   over SSH (the person runs the copy or confirms it):
   ```
   mkdir -p /etc/drcm/.auth && chmod 700 /etc/drcm/.auth
   dd if=/dev/urandom bs=1024 count=2 of=/etc/drcm/.auth/authkey
   sha1sum /etc/drcm/.auth/authkey | cut -c1-40 > /etc/drcm/.auth/authkey.sha1
   chmod 600 /etc/drcm/.auth/authkey /etc/drcm/.auth/authkey.sha1
   ```
4. Write `/etc/drcm/cm.cfg` from `/etc/drcm/cm_2_node_example.cfg` or
   `cm_4_node_example.cfg` (manual sections 5 and 6). Use
   `ipv4addr_nmcli.sh` for floating IPs on RHEL 8 and later. The file is the
   same on every node.
5. Open the DRCM port in firewalld from each peer (manual section 7):
   `firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="PEER/32" port port="53897" protocol="udp" accept'`
   (and `tcp` for the TCP transport), then `firewall-cmd --reload`.
6. `drcm_server --check-config` on every node: no ERROR lines.
7. Start the primary first, then the others: `systemctl enable --now drcm_server`.
   Check `cm_stat` on every node: every node is up, each resource has one
   owner.

## 5. AI-assisted upgrade from 1.37 (or any 1.41 or older) to 1.49

### 5.1 What changes, and what does not

Verified by installing the 1.37 RPM on RHEL 8 (UBI 8.10) and running
`dnf upgrade` to the 1.49 el8 RPM:

- **No rolling upgrade.** Since 1.42 every cluster message is an
  authenticated v2 frame. A 1.42 or later node and a 1.41 or older node do
  not understand each other: each sees the other as dead and takes over
  its resources. **Stop DRCM on every node of the cluster, upgrade every
  node, then start them.** Plan a maintenance window; the clustered
  services are down while DRCM is stopped (unless the config keeps them
  with `keep_services`, `keep_applications` or `keep_filesystems`).
- **Never run `dnf upgrade` on a node where DRCM is running.** Both the
  1.37 and the 1.49 package scripts run `systemctl try-restart
  drcm_server`, so a running node restarts straight into 1.49 next to 1.37
  peers.
- **Package version order is fine.** The 1.37 RPMs are named
  `...1.37-1.el7.x86_64.x86_64.rpm` (Release `1.el7.x86_64`). Version 1.49
  is higher than 1.37, so `dnf upgrade` takes the el8 1.49 RPM.
- **Kept unchanged:** `/etc/drcm/cm.cfg` (1.49 reads 1.37 config files;
  the old key spellings `ipapddrs_check`, `ipaddr_check` and `logfile_name`
  are still accepted), the auth keys (same files and format), the port,
  and `/etc/sysconfig/drcm_server` (same file; `CMPROC` and `CMPROCNAME`
  are no longer used).
- **Service files:** the 1.37 package's `/etc/systemd/system/drcm_server.service`
  (which ran `/etc/rc.d/init.d/drcm_server`) and the init script are
  removed; 1.49 installs `/usr/lib/systemd/system/drcm_server.service`. If
  DRCM 1.37 was built from source instead of installed as an RPM, those
  two files are not removed and the old unit file would still win: move
  them to the backup folder (5.3, step 4).
- **Edited package files:**
  - Files under `/etc/drcm/resources/`, `/etc/drcm/crontabs/` and
    `/etc/drcm/my_cluster_conf/my_cluster_info.sh` that you edited are
    **kept**; the 1.49 version is saved next to them as `.rpmnew`.
  - Other edited files (for example `/etc/drcm/utils/send_alert.sh` or
    the `file_system_sync` scripts) are **replaced** by the 1.49 version;
    your copy is saved as `.rpmsave`. Re-apply the site changes.
  - `tools/drcm_preflight.sh` lists both kinds for each node.
- **`/etc/drcm/.auth` is reset to root:root mode 700** by the RPM. Set a
  group again if the site used one.
- **Floating IPs:** a 1.37 config that uses `/etc/drcm/resources/ipv4addr.sh`
  keeps working (it uses `ip addr`). On RHEL 8, `ipv4addr_nmcli.sh` is the
  NetworkManager way (manual section 12); switch later as its own change,
  not in the upgrade window.
- **New in 1.42 to 1.49, all optional and off by default:** TCP + TLS
  transport and witness quorum (`tools/migrate_cfg.py`), split brain
  protection (`isolation_check`, `takeover_check`), node standby and timed
  and remote standby, file replication over the internet. See CHANGELOG.md.

### 5.2 Before the window (read-only, on every node)

1. Copy `tools/drcm_preflight.sh` and the 1.49 RPM with its `.sha256sum`
   to each node (for example `/root/drcm_149/`).
2. Run it on each node and save the output:
   ```
   bash /root/drcm_149/drcm_preflight.sh --rpm=/root/drcm_149/drcm_server-1.49-1.el8.x86_64.rpm | tee /root/drcm_149/preflight_$(hostname -s).txt
   ```
   It checks the OS, the installed package, unit files, the config file
   (with the 1.49 binary's `--check-config`, unpacked to a temporary
   folder), the auth keys, edited package files, and shows `cm_stat`. It
   changes nothing. A WARN that DRCM is running is expected at this stage.
3. Compare across nodes: the `authkey sha1` lines must be identical, every
   node must accept the config with the 1.49 binary, and `cm_stat` must
   show a healthy cluster. Fix every FAIL before the window. Hand every
   WARN to the person.
4. Note which node is primary for which resources (from `cm_stat`), and the
   stop order: backup nodes first, the primary last. Start order: primary
   first.

### 5.3 In the window (one step at a time, confirm each)

1. **Back up each node:**
   ```
   B=/root/drcm_backup_$(date +%Y%m%d_%H%M); mkdir -p $B
   cp -a /etc/drcm /etc/sysconfig/drcm_server $B/
   cp -a /etc/systemd/system/drcm_server.service* /etc/rc.d/init.d/drcm_server $B/ 2>/dev/null
   rpm -q drcm_server > $B/package.txt
   ```
2. **Stop DRCM on every node**, backup nodes first, the primary last:
   `systemctl stop drcm_server`. Check `systemctl is-active drcm_server`
   says `inactive` and `pgrep -x drcm_server` prints nothing, on every node,
   before going on. Check the floating IPs are released (`ip -4 addr`).
3. **Upgrade each node** (now safe one at a time, every node is stopped).
   `dnf upgrade` keeps a node on the same package (`drcm_server`, the
   system OpenSSL build on RHEL 8). To move a RHEL 8 node to the
   post-quantum build, after the upgrade and with DRCM still stopped:
   `dnf swap drcm_server drcm_server-openssl35-1.49-1.el8.x86_64.rpm`
   (back: `dnf swap drcm_server-openssl35 drcm_server-1.49-1.el8.x86_64.rpm`).
   The swap keeps cm.cfg, the keys and the service state:
   `dnf -y upgrade /root/drcm_149/drcm_server-1.49-1.el8.x86_64.rpm`
   (use `dnf -y install` if `rpm -q drcm_server` showed no package).
4. **Unit files:** if the pre-flight reported an unowned
   `/etc/systemd/system/drcm_server.service` or `/etc/rc.d/init.d/drcm_server`,
   move them into the backup folder now. Then `systemctl daemon-reload`.
   Check: `systemctl cat drcm_server` shows
   `/usr/lib/systemd/system/drcm_server.service` with
   `ExecStart=/usr/sbin/drcm_server --config-file=${CFGFILE} $ARGS`.
5. **Edited files:** `find /etc/drcm /etc/sysconfig -name '*.rpmnew' -o -name '*.rpmsave'`.
   For each `.rpmsave`, re-apply the site change to the new file. For each
   `.rpmnew`, compare with `diff` and tell the person what 1.49 changed; keep
   the site file unless they decide otherwise. Re-apply any group on
   `/etc/drcm/.auth`.
6. **Check every node:** `drcm_server --version` says 1.49;
   `drcm_server --check-config` has no ERROR lines; `authkey.sha1` is the same
   as before.
7. **Start the primary**: `systemctl start drcm_server`. Wait until
   `cm_stat` on it shows its resources up (about a minute). Then start the
   other nodes one by one.
8. **Verify:** on every node `cm_stat` shows all nodes alive and each
   resource with exactly one owner; the floating IPs answer; the services
   run; `/var/log/drcm/drcm.log` and `journalctl -u drcm_server` have no
   repeated errors (rejected frames mean an auth key or version mismatch).
9. Optional, with the person's OK: a failover test. Put the primary in
   standby (`drcm_server --client --command=standby`), check the backup
   takes the resources, then `--command=unstandby` and check they come
   back.

### 5.4 Roll back (all nodes again, never just one)

A 1.49 node cannot run next to 1.37 nodes, so a rollback is the same as the
upgrade in reverse: stop DRCM on every node; on each node
`rpm -Uvh --oldpackage <the 1.37 RPM>` (or reinstall the source build), copy
the files back from the backup folder (`/etc/drcm`, the sysconfig file, the
old unit file and init script), `systemctl daemon-reload`; start the
primary, then the others.

### 5.5 Upgrading from 1.42 or later

1.42 and later speak the same protocol, so a rolling upgrade works: on
each node in turn, put it in standby (1.43 and later), stop DRCM, back up,
`dnf upgrade`, check, start, unstandby, and wait for `cm_stat` to be
healthy before the next node. 1.42 nodes ignore standby: upgrade backup
nodes first. Remote standby (`-n"node"`) needs 1.47 on both nodes.

## 6. After the upgrade (separate changes, each with its own OK)

- Post-quantum TLS (1.49 and later, TCP transport only): check
  `drcm_server --version` on every node shows OpenSSL 3.5 or later with
  the post-quantum key exchange, then look for "key exchange
  X25519MLKEM768 (post-quantum hybrid)" lines in `/var/log/drcm/drcm.log`.
  Once every node runs 1.49, propose `tls_min_version = 1.3` and, if the
  site wants it, `tls_pq_only = 1` (manual section 8, Post-quantum key
  exchange). The cluster authkey HMAC is not affected by quantum
  computers; nothing to change there.
- Floating IPs: move from `ipv4addr.sh` to `ipv4addr_nmcli.sh` (manual
  sections 6 and 12).
- TCP + TLS and witness quorum: `python3 tools/migrate_cfg.py --tcp ...
  /etc/drcm/cm.cfg -o cm.cfg.new`, review, then roll out (manual sections
  9, 10 and 13).
- Split brain protection for clusters across sites: `isolation_check`,
  `takeover_check` (CHANGELOG.md, the 1.43 entry; the manual
  does not cover them in detail yet).

## 7. AI-assisted troubleshooting and support

Manual: sections 11 (running, stats and logs) and 16 (troubleshooting).
Diagnose read-only first; change nothing until the person agrees on the
cause and the fix (rule 2).

### 7.1 Where to look

| What | Command or file |
| --- | --- |
| Cluster view from this node | `drcm_server --client --command=cm_stat` (every node, its state, the resources and where they run) |
| Can this node reach the others | `drcm_server --client --command=ping` (`-n"node"` for one node) |
| Raw stats from every node | `drcm_server --client --command=rstats` |
| Loaded configuration | `drcm_server --client --command=printcfg` |
| Config file errors | `drcm_server --check-config` |
| Server log | `/var/log/drcm/drcm.log`, `journalctl -u drcm_server` |
| Resource logs | `/var/log/drcm/ipv4addr_resource.log` (floating IPs, IPv4 and IPv6), `service_resource.log`, `application_resource.log`, `filesystem_resource.log`, `crontab_resource.log` |
| Service state | `systemctl status drcm_server` |
| Whole-node summary | `tools/drcm_preflight.sh` (read-only) |

Run the same read-only commands on every node and compare: most problems
show up as two nodes disagreeing.

### 7.2 Common problems

- **The service does not start.** Read `systemctl status drcm_server` and
  `journalctl -u drcm_server`, then `drcm_server --check-config`. Usual
  causes: an ERROR in the config file, the host name not matching any
  node in the config, a missing or unreadable auth key, `authkey.sha1`
  not 40 hex characters, missing TLS files in TCP mode. After an upgrade
  from 1.37, an old `/etc/systemd/system/drcm_server.service` that still
  runs `/etc/rc.d/init.d/drcm_server` (5.3, step 4).
- **Nodes see each other as dead, ping fails or frames are rejected.**
  Compare `authkey.sha1` on every node (must be equal), the DRCM version on
  every node (1.42 or later everywhere, or 1.41 or older everywhere), the
  firewalld rules for the port from each peer (`firewall-cmd --list-all`),
  `keep_alive_ip` and `bind_to_keep_alive_ip` in the config, and in TCP
  mode the certificates (manual section 16). With `replay_window_secs`
  set, check the clocks (`chronyc tracking`).
- **A floating IP does not come up or does not move.** Read
  `/var/log/drcm/ipv4addr_resource.log`. With the nmcli scripts the
  NetworkManager connection name must equal the device name. On AWS check
  the AWS CLI, the instance role and the allocation or route table id
  (manual section 12). Running the resource script by hand is a change:
  ask first.
- **A service or application keeps stopping and starting.** Read
  `service_resource.log` or `application_resource.log`: the check or ensure
  script is failing, or the service fails on its own. Fix the service
  first; do not raise check intervals or `dead_node_count` to hide it.
- **No failover with quorum on.** The node cannot reach
  `witness_endpoint`; check the witness's auth key and certificate.
- **Very large logs.** `debug = 0` and a lower `log_level` in the config.

### 7.3 Stop and escalate at once

Do not try to fix these yourself. Report to the person straight away, with
the summary in 7.4:

- **Possible split brain:** `cm_stat` on two nodes shows the same resource
  running on both, the same floating IP answers from two nodes, or the same
  application runs on two nodes.
- Nodes that cannot see each other while both hold resources.
- Any sign of data loss or two writers on shared or replicated storage
  (file system sync, NFS, CIFS, database sync).
- Anything that would need stopping DRCM on more than one node, forcing a
  standby (`--force`), changing the auth key, or turning off a safety
  setting (rule 6).

### 7.4 Support summary

When a problem is not solved, give the person a summary they can send to
their team or to DataReel (https://datareel.com/contact.php). AI-assisted
support ends here: the people take it from this summary.

1. DRCM version and OS on every node (`drcm_server --version`,
   `/etc/os-release`), and whether the cluster uses UDP or TCP.
2. The `tools/drcm_preflight.sh` output from every node involved.
3. `cm_stat` from every node.
4. The log lines around the problem from `drcm.log`, the resource log and
   `journalctl -u drcm_server` (times included).
5. What happened, when, what changed before it, and every command already
   tried with its result.

Remove host names, addresses and other site data from the summary when the
person asks for that, and never include the auth keys, TLS private keys or
passwords.

DRCM is free software under the GNU General Public License, provided as
is. Check every command an agent proposes before it runs; the person
running the cluster is responsible for the changes made.

## 8. Report back

End every task with: the nodes touched, each command and its result, the
pre-flight summaries, every WARN and what was decided, the `.rpmnew` and
`.rpmsave` files and what was done with them, and the final `cm_stat`.
