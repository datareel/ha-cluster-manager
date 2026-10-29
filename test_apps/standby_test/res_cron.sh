#!/bin/bash
# crontab resource: template install_location start|stop
exec /test/res.sh cron $(basename $1) $3
