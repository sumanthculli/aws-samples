#3. Register the custom resource

aws cloudformation register-type \
  --type RESOURCE \
  --type-name Custom::CertManagerCertificate \
  --schema-handler-package s3://your-bucket/cert-manager-certificate-schema.json \
  --execution-role-arn arn:aws:iam::your-account-id:role/your-execution-role

#Create an AWS Config rule that uses your Lambda function:
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
