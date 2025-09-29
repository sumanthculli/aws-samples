 #!/bin/bash
 #set -x

function getNamespaces() {
  namespaces=$(kubectl get --no-headers namespace | tr -s '  ' | cut -d ' ' -f 1 )
  #IFS=$' ' read -d '' -r -a k8namespaces <<< $namespaces
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
export KUBECONFIG=/root/.kube/config
executeCommands 'arn:aws:eks:us-west-2:889195446400:cluster/aexp-v4-cluster'
