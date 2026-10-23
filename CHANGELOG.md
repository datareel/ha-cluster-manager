# Changelog

All notable changes to the DataReel Cluster Manager (DRCM) are recorded
in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
