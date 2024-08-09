aws ec2 create-launch-template \
--launch-template-name eks-lt-mng \
--version-description "Launch template with security group" \
--launch-template-data '{
  "ImageId": "ami-xxxxxxxx", 
  "InstanceType": "m5.4xlarge",
  "SecurityGroupIds": ["sg-0a1b2c3d4e5f6g7h8"],
  "BlockDeviceMappings": [
    {
      "DeviceName": "/dev/xvda",
      "Ebs": {
        "VolumeSize": 50
      }
    }
  ]
}'
