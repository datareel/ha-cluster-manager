#!/bin/bash
# DR cluster resource script for moving a floating IP on AWS (Phase 4).
#
# On AWS a "floating IP" is not a local interface alias; it is an Elastic IP
# (or a VIP routed by a VPC route table) that must be re-pointed at whichever
# instance is currently active. This script is a drop-in replacement for
# ipv4addr.sh and takes the same positional arguments the cluster manager
# passes to every IPv4 resource script, so it is configured the same way:
#
#   ${1} = IP address / resource id. Either an Elastic IP allocation id
#          (eipalloc-xxxxxxxx) to reassociate, or a VIP (e.g. 10.0.12.50)
#          to steer with a VPC route table (see CM_AWS_ROUTE_TABLE_ID below).
#   ${2} = Netmask / CIDR (used only in route-table mode; /32 if empty).
#   ${3} = Interface name (unused on AWS; accepted for argument compatibility).
#   ${4} = action: start | stop | watch
#
# AWS specifics are read from the environment (set them in the cluster
# service environment, an instance profile, or ~/.bashrc):
#
#   CM_AWS_EIP_ALLOC_ID   Elastic IP allocation id, if ${1} is not one.
#   CM_AWS_ROUTE_TABLE_ID VPC route table id; when set, ${1} is treated as a
#                         VIP and a route for it is pointed at this instance's
#                         ENI instead of associating an Elastic IP.
#   CM_AWS_REGION         Overrides the region discovered from instance metadata.
#   AWS_PROFILE / AWS_*   Standard AWS CLI credential variables (an instance
#                         role with ec2:AssociateAddress / ec2:DisassociateAddress
#                         / ec2:ReplaceRoute / ec2:DescribeAddresses is recommended).
#
# The AWS CLI v2 must be installed and reachable.

if [ -f ~/.bashrc ]; then . ~/.bashrc; fi

error_level=0

if [ -z "${1}" ]; then echo "ERROR - You must specify an Elastic IP allocation id or a VIP"; error_level=1; fi
if [ -z "${4}" ]; then echo "ERROR - You must specify an action"; error_level=1; fi
if [ $error_level -ne 0 ]; then
    echo "Usage: ${0} <eipalloc-xxxx|VIP> <netmask> <interface> start|stop|watch"
    exit $error_level
fi

if ! command -v aws >/dev/null 2>&1; then
    echo "ERROR - AWS CLI (aws) is not installed or not in PATH"
    exit 1
fi

RES_ID="${1}"
NETMASK="${2:-32}"

# --- Instance metadata via IMDSv2 (falls back to IMDSv1) ---------------------
imds() { # imds <path>
    local tok
    tok=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
            -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
    if [ -n "$tok" ]; then
        curl -s -H "X-aws-ec2-metadata-token: $tok" \
            "http://169.254.169.254/latest/meta-data/${1}" 2>/dev/null
    else
        curl -s "http://169.254.169.254/latest/meta-data/${1}" 2>/dev/null
    fi
}

INSTANCE_ID=$(imds instance-id)
if [ -z "$INSTANCE_ID" ]; then
    echo "ERROR - Could not read this instance's id from instance metadata (not on EC2?)"
    exit 1
fi

if [ -n "$CM_AWS_REGION" ]; then
    REGION="$CM_AWS_REGION"
else
    REGION=$(imds placement/region)
    [ -z "$REGION" ] && REGION=$(imds placement/availability-zone | sed 's/[a-z]$//')
fi
AWS="aws --region ${REGION:-us-east-1}"

# Primary ENI of this instance (first MAC in metadata).
MAC=$(imds network/interfaces/macs/ | head -n1 | tr -d '/')
ENI_ID=$(imds "network/interfaces/macs/${MAC}/interface-id")

# Resolve the Elastic IP allocation id: use ${1} if it is one, else the env.
ALLOC_ID=""
case "$RES_ID" in
    eipalloc-*) ALLOC_ID="$RES_ID" ;;
    *)          ALLOC_ID="$CM_AWS_EIP_ALLOC_ID" ;;
esac

# ---------------------------------------------------------------------------- #
# Route-table (VIP) mode: steer a VIP route at this instance's ENI.
# ---------------------------------------------------------------------------- #
route_table_mode() {
    local vip="$RES_ID"
    local cidr="$vip/32"
    case "$NETMASK" in
        *.*.*.*) : ;; # dotted mask ignored; AWS routes use /32 for a VIP
        ''|32)   cidr="$vip/32" ;;
        *)       cidr="$vip/${NETMASK}" ;;
    esac
    case "${4}" in
        start)
            echo "Pointing route ${cidr} at ENI ${ENI_ID} in ${CM_AWS_ROUTE_TABLE_ID}"
            $AWS ec2 replace-route --route-table-id "$CM_AWS_ROUTE_TABLE_ID" \
                --destination-cidr-block "$cidr" --network-interface-id "$ENI_ID" 2>/dev/null \
            || $AWS ec2 create-route --route-table-id "$CM_AWS_ROUTE_TABLE_ID" \
                --destination-cidr-block "$cidr" --network-interface-id "$ENI_ID"
            return $?
            ;;
        stop)
            echo "INFO - leaving route ${cidr} in place; the active node will re-point it"
            return 0
            ;;
        watch)
            local owner
            owner=$($AWS ec2 describe-route-tables --route-table-ids "$CM_AWS_ROUTE_TABLE_ID" \
                --query "RouteTables[].Routes[?DestinationCidrBlock=='${cidr}'].NetworkInterfaceId" \
                --output text 2>/dev/null)
            if [ "$owner" = "$ENI_ID" ]; then echo "INFO - this node owns route ${cidr}"; return 0; fi
            echo "WARNING - route ${cidr} is owned by '${owner:-none}', not this node (${ENI_ID})"
            return 1
            ;;
    esac
}

if [ -n "$CM_AWS_ROUTE_TABLE_ID" ] && [ -z "$ALLOC_ID" ]; then
    route_table_mode "$@"
    exit $?
fi

# ---------------------------------------------------------------------------- #
# Elastic IP mode: associate the EIP with this instance.
# ---------------------------------------------------------------------------- #
if [ -z "$ALLOC_ID" ]; then
    echo "ERROR - No Elastic IP allocation id (pass eipalloc-... as the IP, or set CM_AWS_EIP_ALLOC_ID),"
    echo "        and no CM_AWS_ROUTE_TABLE_ID set for VIP route mode."
    exit 1
fi

case "${4}" in
    start)
        echo "Associating Elastic IP ${ALLOC_ID} with instance ${INSTANCE_ID}"
        $AWS ec2 associate-address --allocation-id "$ALLOC_ID" \
            --instance-id "$INSTANCE_ID" --allow-reassociation
        error_level=$?
        [ $error_level -ne 0 ] && echo "ERROR - associate-address failed for ${ALLOC_ID}"
        ;;
    stop)
        # Usually unnecessary: the node taking over reassociates. Done only
        # if this node still holds it, and failure is non-fatal.
        assoc=$($AWS ec2 describe-addresses --allocation-ids "$ALLOC_ID" \
            --query "Addresses[0].InstanceId" --output text 2>/dev/null)
        if [ "$assoc" = "$INSTANCE_ID" ]; then
            assoc_id=$($AWS ec2 describe-addresses --allocation-ids "$ALLOC_ID" \
                --query "Addresses[0].AssociationId" --output text 2>/dev/null)
            echo "Disassociating Elastic IP ${ALLOC_ID} from this instance"
            $AWS ec2 disassociate-address --association-id "$assoc_id" 2>/dev/null
        else
            echo "INFO - Elastic IP ${ALLOC_ID} is not associated with this instance; nothing to stop"
        fi
        error_level=0
        ;;
    watch)
        assoc=$($AWS ec2 describe-addresses --allocation-ids "$ALLOC_ID" \
            --query "Addresses[0].InstanceId" --output text 2>/dev/null)
        if [ "$assoc" = "$INSTANCE_ID" ]; then
            echo "INFO - this node holds Elastic IP ${ALLOC_ID}"
            error_level=0
        else
            echo "WARNING - Elastic IP ${ALLOC_ID} is held by '${assoc:-none}', not this node"
            error_level=1
        fi
        ;;
    *)
        echo "ERROR - Action not valid ${4}"
        exit 1
        ;;
esac

exit $error_level

# End of resource script
