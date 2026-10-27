# My site specific cluster info used by the DRCM utils and file system sync
# scripts. This is a BASH include, sourced as needed

# Set a simple cluster name, any name you will recognize 
# this cluster as, no spaces.
export CLUSTER_NAME=""

# Set IP or hostname of online storage server for shared backups
export BACKUP_STORAGE_SERVER=""

# Set the destination directory on the storage server
export BACKUP_STORAGE_LOCATION=""

# Set the user name that runs you backups. 
# NOTE: This user name must have keyed SSH authentication access
# NOTE: to the cluster nodes and backup storage server
export BACKUP_USER=""

# 
# Set the following for 2-way file system replication 
#
# IP address and Ethernet Interface of the cluster node with primary 
# file systems. File systems on this node will be replicated to the 
# backup file system in the event of a fail over to the backup node.
export PRIMARY_FILESYSTEMS_IP=""
export PRIMARY_FILESYSTEMS_ETH=""
#
# IP address and Ethernet Interface of the backup for this cluster node, 
# where the primary file systems are mirrored too. When the primary
# node is down this node will host the file systems. 
export BACKUP_FILESYSTEMS_IP=""
export BACKUP_FILESYSTEMS_ETH=""

# Allow RSYNC on a diffent IP/Interface if high bandwidth required to sync file systems
## export PRIMARY_FILESYSTEMS_RSYNC_IP=""
## export BACKUP_FILESYSTEMS_RSYNC_IP=""

# Nodes that reach each other through a tunnel or over the internet
# (no shared LAN). Set the role by host name (hostname -s) instead of
# the _ETH interfaces, set the _IP VARs above to ssh host aliases, and
# give the DRCM keep_alive_ip of each node for drcm_server --client.
## export PRIMARY_FILESYSTEMS_HOST=""
## export BACKUP_FILESYSTEMS_HOST=""
## export PRIMARY_FILESYSTEMS_KEEPALIVE_IP=""
## export BACKUP_FILESYSTEMS_KEEPALIVE_IP=""
# Check the other node with ssh, a ping of a tunnel address always answers
## export NODE_UP_CHECK="ssh"
# Ssh options for every ssh, scp and rsync to the other node
## export DRCM_SSH_OPTS="-o StrictHostKeyChecking=accept-new"

# Check for override file. 
#
# NOTE: To create an override file to set the VARs above, do the following:
#
# cat /etc/drcm/my_cluster_info/my_cluster_info.sh > /etc/drcm/my_cluster_info/$(hostname -s).sh
# chmod 644 /etc/drcm/my_cluster_info/$(hostname -s).sh
# vi /etc/drcm/my_cluster_info/$(hostname -s).sh 
#
# Set the cluster VARs. This must be done on the primary and backup file system nodes. Both
# nodes must all VARs set to the same values. 
#
if [ -f  /etc/drcm/my_cluster_info/$(hostname -s).sh ]; then 
    . /etc/drcm/my_cluster_info/$(hostname -s).sh
fi
