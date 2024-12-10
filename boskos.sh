#!/bin/bash

set -e

NAMESPACE="test-pods"

BOSKOS_FOLDER="./boskos"
IBM_JANITOR_FOLDER="./ibm-janitor"

clear_resources() {
  local namespace=$1
  echo "Clearing all resources in namespace $namespace..."
  kubectl delete all --all -n $namespace --ignore-not-found || { echo "Failed to clear resources in namespace $namespace"; exit 1; }
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

clear_resources $NAMESPACE

echo "Applying YAML files from $BOSKOS_FOLDER and $IBM_JANITOR_FOLDER..."
kubectl apply -f $BOSKOS_FOLDER || { echo "Failed to apply YAML files from $BOSKOS_FOLDER"; exit 1; }
kubectl apply -f $IBM_JANITOR_FOLDER || { echo "Failed to apply YAML files from $IBM_JANITOR_FOLDER"; exit 1; }

wait_for_resources $NAMESPACE

echo "Fetching API key from secret..."
API_KEY=$(kubectl get secret ibmcloud-janitor-secret -n $NAMESPACE -o jsonpath="{.data.key}" | base64 --decode)
if [ -z "$API_KEY" ]; then
  echo "Failed to fetch API key from secret or the key is empty"
  exit 1
fi

if kubectl get pod debug-pod -n $NAMESPACE &>/dev/null; then
  echo "Debug pod already exists. Deleting it..."
  kubectl delete pod debug-pod -n $NAMESPACE --ignore-not-found || { echo "Failed to delete existing debug pod"; exit 1; }
fi

echo "Creating a debug pod..."
kubectl run debug-pod --image=ubuntu:latest -n $NAMESPACE --command -- sleep infinity || { echo "Failed to create debug pod"; exit 1; }

echo "Waiting for debug pod to be ready..."
kubectl wait --for=condition=Ready pod/debug-pod -n $NAMESPACE --timeout=120s || { echo "Debug pod did not become ready"; exit 1; }

echo "Installing curl in the debug pod..."
kubectl exec -n $NAMESPACE debug-pod -- apt-get update || { echo "Failed to update apt-get in debug pod"; exit 1; }
kubectl exec -n $NAMESPACE debug-pod -- apt-get install -y curl || { echo "Failed to install curl in debug pod"; exit 1; }

echo "Running curl command inside the debug pod..."
kubectl exec -n $NAMESPACE debug-pod -- curl -X POST -d "{\"api-key\":\"$API_KEY\",\"region\":\"eu-de\",\"resource-group\":\"rZVPCcloudRG\"}" "http://boskos.test-pods.svc.cluster.local/acquire?type=vpc-service&name=lozk8s&state=free&dest=dirty&owner=IBMCloudJanitor" || { echo "Failed to run curl command inside the debug pod"; exit 1; }

echo "Checking the status of resources..."
kubectl get resources -n $NAMESPACE | grep "lozk8s" | grep "dirty" || { echo "Resource lozk8s is not in 'dirty' state"; exit 1; }

clear_resources $NAMESPACE
