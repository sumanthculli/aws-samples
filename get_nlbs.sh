#!/bin/bash
set -e

# Parse input from Terraform
eval "$(jq -r '@sh "ACCOUNT_ID=\(.account_id) ROLE_NAME=\(.role_name) TAG_KEY=\(.tag_key) TAG_VALUE=\(.tag_value) REGION=\(.region)"')"

# Assume role in the source account
CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}" \
  --role-session-name "terraform-nlb-discovery" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo $CREDS | awk '{print $3}')

# Get NLBs with the specified tag
NLB_ARNS=$(aws resourcegroupstaggingapi get-resources \
  --region "${REGION}" \
  --resource-type-filters "elasticloadbalancing:loadbalancer" \
  --tag-filters "Key=${TAG_KEY},Values=${TAG_VALUE}" \
  --query 'ResourceTagMappingList[?contains(ResourceARN, `loadbalancer/net/`)].ResourceARN' \
  --output text | tr '\t' ',')

# Return JSON output to Terraform
jq -n --arg arns "$NLB_ARNS" '{"nlb_arns":$arns}'
