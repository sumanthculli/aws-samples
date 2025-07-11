# Watch pod events in real-time
kubectl get events --watch --field-selector involvedObject.kind=Pod

# Get specific pod events with timestamps
kubectl describe pod <pod-name> -n <namespace>

#!/bin/bash
POD_NAME=$1
NAMESPACE=${2:-default}

echo "Monitoring pod: $POD_NAME in namespace: $NAMESPACE"

# Get initial timestamp when pod is pending
PENDING_TIME=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.metadata.creationTimestamp}')
echo "Pod created at: $PENDING_TIME"

# Wait for pod to be running
while true; do
  STATUS=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.phase}')
  if [ "$STATUS" = "Running" ]; then
    RUNNING_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "Pod running at: $RUNNING_TIME"
    break
  fi
  sleep 1
done

# Calculate duration (requires date parsing)
echo "Use kubectl events or logs for precise timing"


# Get pod creation and running timestamps
kubectl get pod <pod-name> -n <namespace> -o json | jq -r '
  .metadata.creationTimestamp as $created |
  (.status.conditions[] | select(.type=="Ready" and .status=="True") | .lastTransitionTime) as $ready |
  "Created: \($created), Ready: \($ready)"
'

# Check Karpenter node provisioning time
kubectl logs -n karpenter deployment/karpenter --follow | grep -E "(provisioning|launched)"

# Get Karpenter metrics
kubectl port-forward -n karpenter svc/karpenter 8080:8080
curl localhost:8080/metrics | grep karpenter_nodes


# Pod Creation Time: metadata.creationTimestamp

# Node Provisioning Start: Karpenter logs show "provisioning node"

# Node Ready Time: Node condition Ready=True

# Pod Scheduled Time: Pod condition PodScheduled=True

# Pod Running Time: Pod phase becomes Running

