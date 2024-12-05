#!/bin/bash

NAMESPACE="test-pods"
BOSKOS_FOLDER="./boskos"
IBM_JANITOR_FOLDER="./ibm-janitor"
clear_resources() {
  local namespace=$1
  echo "Clearing all resources in namespace $namespace..."
  kubectl delete all --all -n $namespace --ignore-not-found
}
wait_for_resources() {
  local namespace=$1
  echo "Waiting for all resources in namespace $namespace to be running..."
  while true; do
    not_ready=$(kubectl get pods -n $namespace --no-headers | grep -v "Running\|Completed" | wc -l)
    if [ "$not_ready" -eq "0" ]; then
      echo "All resources are up and running in namespace $namespace."
      break
    fi
    echo "Waiting for resources to become ready..."
    sleep 5
  done
}

echo "Applying YAML files from $BOSKOS_FOLDER and $IBM_JANITOR_FOLDER..."
kubectl apply -f $BOSKOS_FOLDER
kubectl apply -f $IBM_JANITOR_FOLDER

wait_for_resources $NAMESPACE

echo "Fetching API key from secret..."
API_KEY=$(kubectl get secret ibmcloud-janitor-secret -n $NAMESPACE -o jsonpath="{.data.api-key}" | base64 --decode)

echo "Creating a debug pod..."
kubectl run debug-pod --image=ubuntu:latest -n $NAMESPACE --command -- sleep infinity

echo "Waiting for debug pod to be ready..."
kubectl wait --for=condition=Ready pod/debug-pod -n $NAMESPACE --timeout=120s

echo "Running curl command inside the debug pod..."
kubectl exec -it debug-pod -n $NAMESPACE -- curl -X POST -d "{\"api-key\":\"$API_KEY\",\"region\":\"eu-de\",\"resource-group\":\"rZVPCcloudRG\"}" "http://boskos.test-pods.svc.cluster.local/acquire?type=vpc-service&name=lozk8s&state=free&dest=dirty&owner=IBMCloudJanitor"

echo "Checking the status of resources..."
kubectl get resources -n $NAMESPACE | grep "lozk8s" | grep "dirty"

echo "Script completed successfully!"
