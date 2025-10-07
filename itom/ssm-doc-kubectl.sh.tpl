 #!/bin/bash
 #set -x

function getNamespaces() {
  namespaces=$(kubectl get --no-headers namespace | tr -s '  ' | cut -d ' ' -f 1 )
  IFS=$'\n' k8namespaces=($(kubectl get --no-headers namespace | awk '{print $1}'))
}

function execKubectlNamespaceCommands(){
  echo "Executing $1 $2 $3 $4"
  kubectl get $1 -n $2 -o $3 |  sed 's/^/###/' | sed "s/###/###$4###/"
}

function execKubectlGetNamespaces(){
  kubectl get $1 -o $2 |  sed "s/^/###$3### /"
}

function executeCommands(){
  kubectl config use-context $1
  getNamespaces
  for ((n=0;n<$${#k8namespaces[@]};n++)); do
    echo $${k8namespaces[$n]} | sed 's/^/#NAMESPACES/'
  done
  execKubectlGetNamespaces namespace json NAMESPACES-JSON
  for ((n=0;n<$${#k8namespaces[@]};n++)); do
    execKubectlNamespaceCommands pods $${k8namespaces[n]} json PODS-JSON
    #echo "Executing Deployments"
    execKubectlNamespaceCommands deployments $${k8namespaces[$n]} json DEPLOYMENTS-JSON
    #echo "Executing Services"
    execKubectlNamespaceCommands services $${k8namespaces[$n]} json SERVICES-JSON
    execKubectlNamespaceCommands replicasets $${k8namespaces[$n]} json REPLICASETS-JSON
    execKubectlNamespaceCommands daemonset $${k8namespaces[$n]} json DAEMONSET-JSON
  done

  kubectl get nodes -o json | sed 's/^/#NODES-JSON#/'
}

# Function to get all EKS cluster ARNs
function getAllEKSClusters() {
  # Get region and account ID
  region=$(aws configure get region 2>/dev/null || echo "us-west-2")
  account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
  
  if [ -z "$account_id" ]; then
    echo "Error: Unable to get AWS account ID"
    exit 1
  fi
  
  # Get all EKS clusters
  clusters=$(aws eks list-clusters --query 'clusters[]' --output text 2>/dev/null)
  
  if [ -z "$clusters" ]; then
    echo "No EKS clusters found in region $region"
    return 1
  fi
  
  # Create array of cluster ARNs
  cluster_arns=()
  for cluster_name in $clusters; do
    cluster_arn="arn:aws:eks:$${region}:$${account_id}:cluster/$${cluster_name}"
    cluster_arns+=("$cluster_arn")
  done
  
  # Return the array (print each ARN on a new line)
  printf '%s\n' "$${cluster_arns[@]}"
}

# Function to process all clusters
function processAllClusters() {
  echo "Discovering EKS clusters..."
  
  # Get all cluster ARNs
  mapfile -t all_clusters < <(getAllEKSClusters)
  
  if [ $${#all_clusters[@]} -eq 0 ]; then
    echo "No EKS clusters found to process"
    exit 1
  fi
  
  echo "Found $${#all_clusters[@]} EKS cluster(s)"
  
  # Iterate through each cluster and execute commands
  for cluster_arn in "$${all_clusters[@]}"; do
    echo "=================================================="
    echo "Processing cluster: $cluster_arn"
    echo "=================================================="
    
    # Call executeCommands for each cluster
    executeCommands "$cluster_arn"
    
    echo ""
    echo "Completed processing cluster: $cluster_arn"
    echo ""
  done
  
  echo "All clusters processed successfully"
}

export KUBECONFIG=/root/.kube/config
processAllClusters
