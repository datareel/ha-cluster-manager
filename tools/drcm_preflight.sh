#!/bin/bash
# DRCM upgrade pre-flight check (read-only).
#
# Run as root on ONE cluster node before upgrading DRCM (for example 1.37 to
# 1.48). It changes nothing on the node: it only reads files, rpm data and
# systemd state, and runs read-only DRCM client commands. With --rpm it unpacks
# the new RPM into a temporary folder (removed at the end) to run the new
# binary's --check-config against this node's current config file.
#
#   tools/drcm_preflight.sh
#   tools/drcm_preflight.sh --rpm=/path/drcm_server-1.48-1.el8.x86_64.rpm
#   tools/drcm_preflight.sh --rpm=... --cfg=/etc/drcm/cm.cfg --no-cluster
#
# Output: one line per check, starting with OK, INFO, WARN or FAIL, then a
# summary. Exit status: 0 = no FAIL, 1 = at least one FAIL, 2 = usage error.
# WARN lines need a person to read them before the upgrade; FAIL lines must be
# fixed first. Run it on every node and keep each node's output.

RPM_FILE=""
CFG=""
CLUSTER=1
for a in "$@"; do
    case "$a" in
        --rpm=*) RPM_FILE="${a#--rpm=}" ;;
        --cfg=*) CFG="${a#--cfg=}" ;;
        --no-cluster) CLUSTER=0 ;;
        -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown argument: $a (see --help)"; exit 2 ;;
    esac
done

NFAIL=0; NWARN=0
ok()   { echo "OK    $*"; }
info() { echo "INFO  $*"; }
warn() { echo "WARN  $*"; NWARN=$((NWARN+1)); }
fail() { echo "FAIL  $*"; NFAIL=$((NFAIL+1)); }

echo "=== DRCM pre-flight on $(hostname) at $(date -u '+%Y-%m-%d %H:%M:%S UTC') ==="
[ "$(id -u)" -eq 0 ] || warn "not running as root: some files (auth keys, logs) cannot be read"

# --- Operating system
if [ -r /etc/os-release ]; then
    . /etc/os-release
    info "OS: ${PRETTY_NAME:-unknown}"
    case "${VERSION_ID%%.*}" in
        8|9|10) ok "RHEL family ${VERSION_ID%%.*} is supported by the 1.48 RPMs (use the el${VERSION_ID%%.*} RPM)" ;;
        *) warn "OS major version ${VERSION_ID:-?} has no 1.48 RPM (RPMs exist for RHEL 8, 9 and 10)" ;;
    esac
fi

# --- Installed DRCM
BIN=/usr/sbin/drcm_server
if [ -x $BIN ]; then
    CUR=$($BIN --version 2>/dev/null | grep -io 'version [0-9.]*' | awk '{print $2}')
    info "installed binary: $BIN, version ${CUR:-unknown}"
else
    fail "no $BIN on this node"
fi
if PKG=$(rpm -q drcm_server 2>/dev/null); then
    info "installed package: $PKG"
    OWNER=$(rpm -qf $BIN 2>/dev/null)
    [ "$OWNER" == "$PKG" ] && ok "$BIN belongs to $PKG" || warn "$BIN is not the packaged file (rpm -qf: ${OWNER:-none}); it was replaced by hand"
else
    warn "drcm_server is not installed as an RPM (built from source?). dnf will install 1.48 over the files, but leftover unpackaged files (unit file, init script) are not removed: see the service checks below"
fi

# --- Service and unit files
OLDUNIT=/etc/systemd/system/drcm_server.service
INITSCRIPT=/etc/rc.d/init.d/drcm_server
for f in $OLDUNIT $INITSCRIPT; do
    if [ -e $f ]; then
        o=$(rpm -qf $f 2>/dev/null)
        if [ -n "$o" ] && [ "${o#*not owned}" == "$o" ]; then
            if rpm -V drcm_server 2>/dev/null | grep -q " $f\$"; then
                warn "$f (from $o) was edited: the upgrade keeps it as $f.rpmsave; check nothing else in /etc/systemd/system overrides the new unit"
            else
                ok "$f belongs to $o and is unedited: the upgrade removes it (1.48 uses /usr/lib/systemd/system/drcm_server.service)"
            fi
        else
            fail "$f is not owned by any package: after the upgrade it would still run the old init script. Move it aside (to a backup) during the upgrade, then systemctl daemon-reload"
        fi
    fi
done
ls -d /etc/systemd/system/drcm_server.service.d 2>/dev/null && warn "drop-in folder /etc/systemd/system/drcm_server.service.d exists: review it against the 1.48 unit (Type=simple, KillMode=process)"
if command -v systemctl >/dev/null 2>&1; then
    info "service: active=$(systemctl is-active drcm_server 2>/dev/null) enabled=$(systemctl is-enabled drcm_server 2>/dev/null)"
fi
if [ -r /etc/sysconfig/drcm_server ]; then
    SYSARGS=$(grep -E '^[[:space:]]*(ARGS|CFGFILE|CMPROC|CMPROCNAME)=' /etc/sysconfig/drcm_server)
    [ -n "$SYSARGS" ] && info "/etc/sysconfig/drcm_server sets: $(echo $SYSARGS)"
    echo "$SYSARGS" | grep -q -E '^[[:space:]]*CMPROC' && warn "CMPROC/CMPROCNAME in /etc/sysconfig/drcm_server are ignored by the 1.48 unit (it always runs /usr/sbin/drcm_server)"
    [ -z "$CFG" ] && CFG=$(echo "$SYSARGS" | sed -n 's/^[[:space:]]*CFGFILE=["]\{0,1\}\([^"]*\)["]\{0,1\}.*/\1/p' | tail -1)
fi
[ -z "$CFG" ] && CFG=/etc/drcm/cm.cfg

# --- Config file
if [ -r "$CFG" ]; then
    ok "config file $CFG ($(wc -l < "$CFG") lines, sha256 $(sha256sum "$CFG" | cut -c1-16)...)"
    grep -q -E '^[[:space:]]*cluster_transport[[:space:]]*=[[:space:]]*tcp' "$CFG" && info "cluster_transport = tcp" || info "cluster transport: UDP (the default, also used by 1.37)"
    for s in $(grep -o -E '/etc/drcm/resources/[A-Za-z0-9_.-]+\.sh' "$CFG" | sort -u); do
        [ -x "$s" ] || fail "$CFG uses $s, which is missing or not executable"
    done
    grep -q -E '/etc/drcm/resources/ipv4addr\.sh' "$CFG" && info "floating IPs use the legacy ipv4addr.sh (ip addr). It still works in 1.48; ipv4addr_nmcli.sh is the NetworkManager script for RHEL 8 and later. Change it later as a separate step, not during the upgrade"
else
    fail "cannot read the config file $CFG (use --cfg=FILE)"
fi

# --- Auth keys (same files and format in 1.37 and 1.48)
AK=/etc/drcm/.auth/authkey; AS=/etc/drcm/.auth/authkey.sha1
if [ -r $AK ] && [ -r $AS ]; then
    SZ=$(stat -c %s $AK)
    [ "$SZ" -ge 2048 ] && ok "authkey is $SZ bytes" || warn "authkey is only $SZ bytes (the README makes 2048)"
    if grep -q -E '^[0-9a-f]{40}$' $AS; then
        [ "$(sha1sum $AK | cut -c1-40)" == "$(cat $AS)" ] && ok "authkey.sha1 matches authkey" || fail "authkey.sha1 does not match authkey"
    else
        fail "authkey.sha1 is not a 40 character hex hash (1.42 and later refuse to start)"
    fi
    info "authkey sha1 (compare on every node, they must be equal): $(cat $AS)"
    for f in /etc/drcm/.auth $AK $AS; do
        m=$(stat -c %a $f); [ $((8#$m & 8#007)) -eq 0 ] || warn "$f is mode $m: other users can read it (1.42 and later warn; use 700 for the folder, 600 for the keys)"
    done
    [ "$(stat -c %G /etc/drcm/.auth)" != "root" ] && warn "/etc/drcm/.auth group is $(stat -c %G /etc/drcm/.auth): the RPM upgrade resets it to root:root 0700, set it again after the upgrade"
else
    fail "cannot read $AK and $AS"
fi

# --- Package config files that were edited (what the upgrade does with them)
if [ -n "$PKG" ]; then
    MOD=$(rpm -V drcm_server 2>/dev/null | awk '$1 ~ /5/ && $2 == "c" {print $3}')
    if [ -z "$MOD" ]; then
        ok "no packaged config file was edited"
    else
        for f in $MOD; do
            case "$f" in
                /etc/drcm/resources/*|/etc/drcm/crontabs/*|/etc/drcm/my_cluster_conf/my_cluster_info.sh)
                    warn "edited $f: KEPT by the upgrade, the 1.48 version is written as $f.rpmnew. Compare them after the upgrade" ;;
                /etc/sysconfig/drcm_server)
                    info "edited $f: kept (same file in 1.37 and 1.48)" ;;
                *)
                    warn "edited $f: REPLACED by the 1.48 version, your copy is saved as $f.rpmsave. Re-apply your changes after the upgrade" ;;
            esac
        done
    fi
fi
OLDSAVE=$(find /etc/drcm /etc/sysconfig -name '*.rpmnew' -o -name '*.rpmsave' 2>/dev/null | grep drcm)
[ -n "$OLDSAVE" ] && warn ".rpmnew/.rpmsave files from an earlier upgrade already exist: $(echo $OLDSAVE)"

# --- Network and firewall
command -v nmcli >/dev/null 2>&1 && info "NetworkManager: $(nmcli -t -f RUNNING general 2>/dev/null)" || info "nmcli not found"
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    PORT=$(grep -E '^[[:space:]]*(udpport|tcpport)' "$CFG" 2>/dev/null | head -1 | awk -F= '{gsub(/ /,"",$2); print $2}')
    info "firewalld running; DRCM port in config: ${PORT:-not set}. The port does not change in 1.48"
fi

# --- Cluster state (read-only client commands of the installed version)
if [ $CLUSTER -eq 1 ] && [ -x $BIN ] && [ "$(systemctl is-active drcm_server 2>/dev/null)" == "active" ]; then
    echo "--- cm_stat (installed version)"
    timeout 60 $BIN --client --command=cm_stat --config-file="$CFG" 2>&1 | tail -40
fi

# --- New binary against the current config
if [ -n "$RPM_FILE" ] && [ "$(systemctl is-active drcm_server 2>/dev/null)" == "active" ]; then
    warn "DRCM is running on this node (fine for planning). Before dnf upgrade, stop it on EVERY node: the package scripts restart a running service, and a 1.48 node cannot talk to 1.41 or older peers (both sides would see the other as dead and take over resources)"
fi
if [ -n "$RPM_FILE" ]; then
    if [ ! -r "$RPM_FILE" ]; then
        fail "cannot read $RPM_FILE"
    else
        if [ -r "$RPM_FILE.sha256sum" ]; then
            (cd "$(dirname "$RPM_FILE")" && sha256sum -c --quiet "$(basename "$RPM_FILE").sha256sum") && ok "$(basename "$RPM_FILE") sha256 matches its .sha256sum" || fail "$(basename "$RPM_FILE") sha256 does NOT match its .sha256sum"
        else
            warn "no $RPM_FILE.sha256sum next to the RPM: check the sha256 against the downloads page by hand"
        fi
        NEW=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$RPM_FILE" 2>/dev/null)
        info "new package: $NEW"
        # RHEL 8 RPMs from 1.49 need OpenSSL 3.5 from EPEL (openssl3-libs)
        if rpm -qp --requires "$RPM_FILE" 2>/dev/null | grep -q '^openssl3-libs'; then
            if rpm -q openssl3-libs >/dev/null 2>&1; then
                ok "openssl3-libs is installed ($(rpm -q openssl3-libs))"
            elif dnf -q list --available openssl3-libs >/dev/null 2>&1; then
                info "openssl3-libs is available (EPEL); dnf installs it with the upgrade"
            else
                fail "$NEW needs openssl3-libs (OpenSSL 3.5) from EPEL, and no enabled repository has it: enable EPEL on this node first"
            fi
        fi
        if [ -n "$PKG" ]; then
            CMP=$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$RPM_FILE" 2>/dev/null)
            OLDVR=$(rpm -q --qf '%{VERSION}-%{RELEASE}' drcm_server)
            PY=$(command -v /usr/libexec/platform-python python3 2>/dev/null | head -1)
            r=$($PY -c "import rpm,sys; a=sys.argv[1].split('-',1); b=sys.argv[2].split('-',1); print(rpm.labelCompare(('0',a[0],a[1]),('0',b[0],b[1])))" "$CMP" "$OLDVR" 2>/dev/null)
            case "$r" in
                1) ok "$NEW is newer than $PKG: dnf upgrade will take it" ;;
                "") info "could not compare versions (python3 rpm module missing)" ;;
                *) fail "$NEW is not newer than $PKG: dnf would not upgrade to it" ;;
            esac
        fi
        T=$(mktemp -d /tmp/drcm_preflight.XXXXXX)
        (cd $T && rpm2cpio "$RPM_FILE" | cpio -id --quiet ./usr/sbin/drcm_server 2>/dev/null)
        if [ -x $T/usr/sbin/drcm_server ]; then
            info "new binary: $($T/usr/sbin/drcm_server --version 2>/dev/null | grep -i version)"
            echo "--- new binary --check-config on $CFG"
            $T/usr/sbin/drcm_server --check-config --config-file="$CFG" --log-disable > $T/check.txt 2>&1
            grep -i -E 'error|warn|has errors|config file' $T/check.txt | tail -30
            grep -q -i 'has errors' $T/check.txt && fail "the 1.48 binary reports errors in $CFG (lines above)" || ok "the 1.48 binary accepts $CFG"
        else
            fail "could not unpack /usr/sbin/drcm_server from $RPM_FILE (rpm2cpio and cpio needed)"
        fi
        rm -rf "$T"
    fi
fi

echo "=== Summary for $(hostname): $NFAIL FAIL, $NWARN WARN ==="
[ $NFAIL -eq 0 ]
