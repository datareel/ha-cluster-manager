DRCM node standby tests

Three DRCM nodes (n1, n2, n3) in rootless podman containers on the
network drcmsbnet (10.89.77.0/24), using UDP keep alives. The
resources are fake (res.sh): each start and stop is written to
shared/events.log, and analyze.py reports every move of a resource
between nodes with its gap and any overlap.

  n1 owns cron1, vip1, svc1, app1 and fs1; n2 backs them all up.
  n2 owns app2 and n3 owns app3; n1 backs up both.

Build drcm_server, then:

  ./setup.sh start /path/to/drcm_server [/path/to/old/drcm_server]
  ./run_tests.sh
  ./setup.sh stop

The optional second binary (for example a 1.42 build) runs the mixed
version test. An AddressSanitizer build of drcm_server works as the
first binary: the image has libasan and libubsan, and any sanitizer
report in run/NODE/log fails the run. Build it in a container with
libasan (RHEL needs the libasan and libubsan packages):

  make CXXFLAGS="-fsanitize=address,undefined -g -O1 -fno-omit-frame-pointer" \
       LINKER_FLAGS="-fsanitize=address,undefined"

Tests:

  1. standby on n1: n2 takes over everything, no overlap, IPs and
     file systems stop after the apps, rstats and cm_stat show it.
  2. DRCM restart on n1 in standby: stays in standby, nothing moves.
  3. Container kill and restart (reboot) of n1 in standby: same.
  4. unstandby: everything returns to n1 with no overlap.
  5. A standby request sent from n2 for n1 is rejected.
  6. With n2 and n3 stopped, standby is refused; --force stops n1's
     own resources and the app2 and app3 backups it took over.
  7. Mixed: n2 runs the old binary. Standby is refused, and with
     --force the old n2 does not take over (no split brain).

fakesu stands in for su in the image: rootless podman maps only uid 0,
so the real su cannot set groups.
