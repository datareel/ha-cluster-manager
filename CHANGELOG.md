# Changelog

All notable changes to the DataReel Cluster Manager (DRCM) are recorded
in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Security
- Commands run through `su` or `sudo` are now shell quoted. Before,
  a single quote in an application start, stop or ensure command
  broke out of the quoting, so the rest of the command ran as the
  cluster user (usually root) instead of the application user.
- Fixed a stack buffer overflow in the config file reader: a
  `[CM_SERVER]` or `[CM_NODE]` value longer than 254 characters was
  copied into a 255 byte buffer with `strcpy()`.
- Fixed a heap buffer overflow in the process log queue. Its counter
  wrapped at `log_queue_size` (2048) instead of `log_queue_proc_size`
  (255), so after 255 process messages (shutdown steps, debug level
  signals) the server wrote past the end of the array.
- Signals are now handled in a dedicated thread with `sigwait()`.
  Before, the whole shutdown (stopping threads, taking locks,
  logging) ran inside the signal handler, which could deadlock or
  corrupt state if the signal arrived while a thread held a lock.
- The `ping`, `rstats`, `cm_stat` and keep alive clients now accept a
  reply only if it has the cluster checkword, the auth hash and an
  ACK. Before, any UDP packet of the right size counted as a reply.
- The stats reply size from another node is limited to 64 KB. Before,
  a reply header could make the client allocate up to 2 GB.
- The server checks that `authkey.sha1` holds a 40 character hex
  hash and warns if either auth file can be read by other users.
- `cifs.sh` passes the CIFS password in a private credentials file
  instead of on the `mount` command line, where `ps` showed it to
  every user.
- `process_lock.sh` and `process_lock_net.sh` created world writable
  lock files (mode 777) and matched PIDs with `grep`, so PID 12 also
  matched 1234. Another user could make a root script kill any
  process. Lock files are now mode 644, PIDs are checked exactly
  with `ps -p`, and only the lock owner's own child processes are
  killed.
- The init script's `stop` matched child processes with `grep` on the
  PID and could kill unrelated processes. It now uses the parent PID.
- SSH and SCP calls in the sync and lock scripts used
  `StrictHostKeyChecking=no`, which accepts any host key. They now
  use `StrictHostKeyChecking=accept-new`, which trusts a key the
  first time and refuses one that changes. Set `DRCM_SSH_OPTS` to
  override. Note that `accept-new` needs OpenSSH 7.6 or newer
  (RHEL 8 and later).
- `nfs.sh` and `cifs.sh` no longer create mount points as mode 777 or
  write to predictable `/tmp/ls.PID` files.
- `send_alert.sh` time stamp files are mode 644 instead of 666, so
  other users cannot suppress alerts.

### Fixed
- Config settings are now matched by their full name. Before, a line
  matched any setting whose name it contained, so `debug_level = 1`
  also turned on `debug` and `verbose_level = 1` turned on `verbose`.
  Every config with those lines ran in debug mode. With this fix the
  `debug` and `verbose` settings work as written.
- The `logfile` setting written in the example configs was ignored
  (the code only read `logfile_name`). Both names are accepted now.
- The `ipapddrs_check` setting written in the example configs was
  ignored (the code read `ipaddr_check`), so floating IPs were always
  checked every 60 seconds. `ipaddrs_check`, `ipaddr_check` and
  `ipapddrs_check` are all accepted now.
- `--check-config` now warns about unknown settings and reports nodes
  with a missing `nodename`, `hostname` or `keep_alive_ip`, and
  duplicate node names or hostnames.
- On shutdown with `keep_services`, `keep_applications` or
  `keep_filesystems` set, failed over (backup) resources were never
  stopped, because their names were compared without the
  `nodename:` prefix. They are stopped now and removed from the
  node's stats.
- A node marked `node_is_active = 0` was still sent keep alives. If
  it answered, its resources failed back to it on the next pass, then
  over again, in a loop. Inactive nodes are no longer probed.
- When several nodes failed at once, the failed keep alive count was
  shared between them, so the second node was declared dead after
  fewer than `dead_node_count` failures. Each node gets its own count.
- The "All active CM nodes failed" message never appeared. It now
  appears when every other active node fails the keep alive check.
- A keep alive timeout was reported as a read error.
- Each resource thread waited the default 60 seconds before its first
  check instead of the node's configured `*_check` time. The file
  system thread also used `applications_check` for its first wait.
- Failover checks matched resource names as substrings, so a node
  running `apps10` looked like it was running `apps1`.
- The stats list could return while holding its lock, which would
  hang every thread that used it.
- The server crashed if the log thread failed to start (it printed
  the error from the UDP thread, which did not exist yet) or if
  `$USER` was not set for a non-root cluster user.
- Command line arguments were processed once per argument.
- Memory from `new[]` in the stats clients was freed with `delete`.
- The UDP server no longer spins at full CPU on a repeating socket
  error.
- `service.sh reload` restarted the service instead of reloading it.
- `ipv4addr_nmcli.sh` always reapplied interface `enp1s0` instead of
  the configured one, and the copy config nmcli scripts printed
  `enp1s0` in their error messages.
- `cifs.sh` never computed password expiry (the test was inverted)
  and its stale handle recovery mounted without the CIFS options.
- `sync_file_system_include.sh`: `RsyncCopy` was missing `-e`, so
  rsync treated the ssh command as a source path. The script now
  exits with an error when a sync fails instead of always exiting 0.
- `manual_fs_failover.sh` named the wrong user in its error message.
- The SysV init script ignored `ARGS` from `/etc/sysconfig/drcm_server`
  (the test was inverted).

### Removed
- Trimmed the bundled DataReel library to the components the DRCM
  server links against. `include/` went from 99 headers to 29 and
  `src/` from 79 source files to 16. The database, RDBMS, B-tree,
  serial port, HTTP/FTP/SMTP/POP3/telnet, XML/RSS, PostScript/HTML
  printing, terminal I/O and OpenSSL components are gone because DRCM
  never used them.
- Removed `build/makefile_ssl` and the `USE_OPEN_SSL` build option.
  DRCM does not use the DataReel SSL extensions.
- Removed compiler defines for the deleted components from
  `env/linux.env` (PostScript, HTML and text printing, database and
  B-tree cache, serial baud rates, terminal I/O, device cache, SSL and
  `__CONSOLE__`).
- Removed unused DataReel includes from the DRCM server sources
  (`gxconfig.h`, `gxtelnet.h`, `gxscomm.h`, `gxbstree.h`,
  `devcache.h`, `memblock.h`, `membuf.h`). `drcm_server.h` now
  includes `gxsocket.h` directly, which `gxtelnet.h` used to pull in.

### Added
- `build/sync_datareel.sh` copies the DataReel files DRCM uses from a
  DataReel source tree, so the bundled copy can be refreshed from the
  upstream repository.
- `CHANGELOG.md` (this file).

### Changed
- `build/makefile`, `env/glibobjs.mak` and `env/glibdeps.mak` now list
  only the 16 bundled library components. Dependency lists were
  regenerated with `g++ -MM`.
- The bundled DataReel files match DataReel 5.10.
- `.gitignore` now ignores the `drcm_server/drcm_server` binary.
