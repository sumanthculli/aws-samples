aws eks create-nodegroup \
--cluster-name eks-lt-01 \
--nodegroup-name eks-lt-ng \
--node-role arn:aws:iam::111122223333:role/role-name \
--subnets "subnet-0e2907431c9988b72" "subnet-04ad87f71c6e5ab4d" "subnet-09d912bb63ef21b9a" \
--scaling-config minSize=1,maxSize=5,desiredSize=4 \
--launch-template name=my-launch-template,version=1 \
--update-config maxUnavailable=2 \
--labels '{"my-eks-nodegroup-label-1": "value-1" , "my-eks-nodegroup-label-2": "value-2"}'
