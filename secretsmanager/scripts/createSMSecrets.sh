#!/bin/bash

# Variables
SECRET_NAME="/dev/eks/ns1"
DESCRIPTION="My test secret created with the API."
SECRET_STRING='{"user":"eksns1","password":"eskns1password"}'
REGION="us-west-2"

# AWS credentials (ensure these are set in your environment or use AWS CLI configured profile)
AWS_ACCESS_KEY_ID="your-access-key-id"
AWS_SECRET_ACCESS_KEY="your-secret-access-key"
SESSION_TOKEN="your-session-token" # Optional, if using temporary credentials

# Generate the current date in the required format
DATE=$(date -u +"%Y%m%dT%H%M%SZ")
DATE_SHORT=$(date -u +"%Y%m%d")

# Create a canonical request
REQUEST_PAYLOAD=$(cat <<EOF
{
  "Name": "$SECRET_NAME",
  "Description": "$DESCRIPTION",
  "SecretString": "$SECRET_STRING"
}
EOF
)

# Hash the payload
PAYLOAD_HASH=$(echo -n "$REQUEST_PAYLOAD" | openssl dgst -sha256 | awk '{print $2}')

# Create canonical headers
CANONICAL_HEADERS="content-type:application/x-amz-json-1.1\nhost:secretsmanager.$REGION.amazonaws.com\nx-amz-date:$DATE\n"
SIGNED_HEADERS="content-type;host;x-amz-date"

# Create the canonical request
CANONICAL_REQUEST="POST
/
content-type:application/x-amz-json-1.1
host:secretsmanager.$REGION.amazonaws.com
x-amz-date:$DATE

$SIGNED_HEADERS
$PAYLOAD_HASH"

# Create the string to sign
ALGORITHM="AWS4-HMAC-SHA256"
CREDENTIAL_SCOPE="$DATE_SHORT/$REGION/secretsmanager/aws4_request"
STRING_TO_SIGN="$ALGORITHM
$DATE
$CREDENTIAL_SCOPE
$(echo -n "$CANONICAL_REQUEST" | openssl dgst -sha256 | awk '{print $2}')"

# Create the signing key
kSecret="AWS4$AWS_SECRET_ACCESS_KEY"
kDate=$(echo -n "$DATE_SHORT" | openssl dgst -sha256 -hmac "$kSecret" | awk '{print $2}')
kRegion=$(echo -n "$REGION" | openssl dgst -sha256 -hmac "$kDate" | awk '{print $2}')
kService=$(echo -n "secretsmanager" | openssl dgst -sha256 -hmac "$kRegion" | awk '{print $2}')
kSigning=$(echo -n "aws4_request" | openssl dgst -sha256 -hmac "$kService" | awk '{print $2}')

# Create the signature
SIGNATURE=$(echo -n "$STRING_TO_SIGN" | openssl dgst -sha256 -hmac "$kSigning" | awk '{print $2}')

# Create the authorization header
AUTHORIZATION_HEADER="$ALGORITHM Credential=$AWS_ACCESS_KEY_ID/$CREDENTIAL_SCOPE, SignedHeaders=$SIGNED_HEADERS, Signature=$SIGNATURE"

# Make the API request
curl -X POST "https://secretsmanager.$REGION.amazonaws.com" \
    -H "Content-Type: application/x-amz-json-1.1" \
    -H "X-Amz-Date: $DATE" \
    -H "Authorization: $AUTHORIZATION_HEADER" \
    -d "$REQUEST_PAYLOAD"
