
#!/bin/bash

# Variables
ROLE_NAME="SecretsManagerABACRole"
POLICY_NAME="SecretsManagerABACPolicy"
TRUST_POLICY_FILE="trust-policy.json"
ABAC_POLICY_FILE="abac-policy.json"

# Create the trust policy JSON file
cat > $TRUST_POLICY_FILE << EOL
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOL

# Create the ABAC policy JSON file
cat > $ABAC_POLICY_FILE << EOL
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:ResourceTag/team": "\${aws:PrincipalTag/team}",
                    "aws:ResourceTag/namespace": "\${aws:PrincipalTag/ns1}"
                }
            }
        }
    ]
}
EOL

# Create the IAM role
aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://$TRUST_POLICY_FILE

# Create the IAM policy
aws iam create-policy --policy-name $POLICY_NAME --policy-document file://$ABAC_POLICY_FILE

# Get the ARN of the created policy
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text)

# Attach the policy to the role
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn $POLICY_ARN

# Clean up local policy files
rm $TRUST_POLICY_FILE $ABAC_POLICY_FILE

echo "IAM Role '$ROLE_NAME' and Policy '$POLICY_NAME' created and attached successfully."
