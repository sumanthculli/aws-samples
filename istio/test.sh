

kubectl -n istio-system get pod -l app=istiod

# Get root certificate hash
kubectl -n istio-system get configmap istio-ca-root-cert -o jsonpath='{.data.root-cert\.pem}' | base64 -d | md5sum

# Get validating webhook CA bundle hash
kubectl get validatingwebhookconfiguration istio-validator-istio-system -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | base64 -d | md5sum

# Get mutating webhook CA bundle hash
kubectl get mutatingwebhookconfiguration istio-sidecar-injector -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | base64 -d | md5sum



# Extract current root certificate
ROOT_CERT=$(kubectl -n istio-system get configmap istio-ca-root-cert -o jsonpath='{.data.root-cert\.pem}' | base64 -w 0)

# Patch validating webhook
kubectl patch validatingwebhookconfiguration istio-validator-istio-system --type='json' -p="[{'op':'replace','path':'/webhooks/0/clientConfig/caBundle','value':'${ROOT_CERT}'}]"

# Patch mutating webhook
kubectl patch mutatingwebhookconfiguration istio-sidecar-injector --type='json' -p="[{'op':'replace','path':'/webhooks/0/clientConfig/caBundle','value':'${ROOT_CERT}'}]"


kubectl rollout restart deployment -n istio-system istiod
kubectl rollout restart deployment -n <application-namespace> <deployment-name>


kubectl logs -n istio-system -l app=istiod | grep -i "caBundle"
