#!/bin/bash

# Check if subnet ID is provided
if [ -z "$1" ]; then
    echo "Please provide a subnet ID"
    exit 1
fi

SUBNET_ID=$1

# Get subnet CIDR and available IP count
SUBNET_INFO=$(aws ec2 describe-subnets --subnet-ids $SUBNET_ID --query 'Subnets[0].[CidrBlock,AvailableIpAddressCount]' --output text)
CIDR=$(echo $SUBNET_INFO | cut -d' ' -f1)
AVAILABLE_IPS=$(echo $SUBNET_INFO | cut -d' ' -f2)

# Calculate total IPs
TOTAL_IPS=$((2 ** (32 - ${CIDR#*/})))

# AWS reserves 5 IPs in each subnet
USABLE_IPS=$((TOTAL_IPS - 5))

# Get list of used IPs
USED_IPS=$(aws ec2 describe-network-interfaces --filters "Name=subnet-id,Values=$SUBNET_ID" --query 'NetworkInterfaces[].PrivateIpAddresses[].PrivateIpAddress' --output text)

echo "Subnet CIDR: $CIDR"
echo "Total IPs: $TOTAL_IPS"
echo "Usable IPs: $USABLE_IPS"
echo "Available IPs: $AVAILABLE_IPS"
echo "Used IPs:"
echo "$USED_IPS"

# Calculate and display unused IPs
echo "Unused IPs:"
IFS='.' read -r -a CIDR_PARTS <<< "${CIDR%/*}"
for i in $(seq $((CIDR_PARTS[3] + 1)) $((CIDR_PARTS[3] + USABLE_IPS))); do
    IP="${CIDR_PARTS[0]}.${CIDR_PARTS[1]}.${CIDR_PARTS[2]}.$i"
    if ! echo "$USED_IPS" | grep -q "$IP"; then
        echo $IP
    fi
done
