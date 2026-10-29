#!/bin/bash
# Fake DRCM resource for the standby tests. Records which node runs each
# resource in /shared/state and every real start and stop in
# /shared/events.log ("epoch_ms host type name start|stop").
# Usage: res.sh type name start|stop|watch|ensure
type=$1; name=$2; action=$3
host=$(hostname -s)
state=/shared/state/${type}.${name}.${host}
event() { echo "$(date +%s%3N) ${host} ${type} ${name} $1" >> /shared/events.log; }
case "$action" in
    start|mount)
	if [ ! -f $state ]; then touch $state; event start; fi ;;
    stop|unmount)
	if [ -f $state ]; then rm -f $state; event stop; fi ;;
    ensure)
	if [ ! -f $state ]; then touch $state; event start; fi ;;
    watch)
	[ -f $state ] || exit 1 ;;
esac
exit 0
