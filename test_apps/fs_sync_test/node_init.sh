#!/bin/bash
mkdir -p /etc/drcm /var/lib/drcm /root/drcmlog
cp -a /drcm_etc/. /etc/drcm/
cp /fake_drcm /usr/sbin/drcm_server
cp /fakessh.py /usr/local/bin/ssh; cp /fakescp /usr/local/bin/scp
/usr/local/bin/ssh --serve > /root/sshd.log 2>&1 &
exec sleep infinity
