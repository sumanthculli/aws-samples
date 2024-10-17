#3. Register the custom resource

aws cloudformation register-type \
  --type RESOURCE \
  --type-name Custom::CertManagerCertificate \
  --schema-handler-package s3://your-bucket/cert-manager-certificate-schema.json \
  --execution-role-arn arn:aws:iam::your-account-id:role/your-execution-role

#4. Create an AWS Config rule that uses your Lambda function:
aws config put-config-rule --config-rule '{
  "ConfigRuleName": "cert-manager-certificates",
  "Source": {
    "Owner": "CUSTOM_LAMBDA",
    "SourceIdentifier": "arn:aws:lambda:your-region:your-account-id:function:your-lambda-function",
    "SourceDetails": [
      {
        "EventSource": "aws.config",
        "MessageType": "ScheduledNotification"
      }
    ]
  },
  "Scope": {
    "ComplianceResourceTypes": [
      "Custom::CertManagerCertificate"
    ]
  }
}'

# This setup will create a custom resource in AWS Config that fetches cert-manager certificates from your EKS cluster. The Lambda function will run periodically to collect certificate data and create configuration items in AWS Config.
# Remember to set up the necessary IAM roles and permissions for the Lambda function to access your EKS cluster and AWS Config. Also, ensure that your Lambda function has network access to your EKS cluster.

