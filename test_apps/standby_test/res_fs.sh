#!/bin/bash
# file system resource: source target mount|unmount|watch
exec /test/res.sh filesystem $(basename $1) $3
