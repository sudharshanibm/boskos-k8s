#!/bin/bash

set -e  # Exit on error

CONFIG_NAME=$1
NAMESPACE="test-pods"
CONFIGMAP_FILE="boskos/boskos-configmap.yaml"
MAX_WAIT=300  # Max wait time in seconds
INTERVAL=5    # Check every 5 seconds

if [ -z "$CONFIG_NAME" ]; then
    echo -e "\033[1;31m❌ Error: Config name is required.\033[0m"
    echo -e "   Usage: ./deploy_boskos.sh <config-name>"
    exit 1
fi

echo -e "\n🔹 \033[1;34mChecking if namespace '$NAMESPACE' exists...\033[0m"
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo -e "🛠️  Namespace '$NAMESPACE' does not exist. Creating..."
    kubectl create namespace "$NAMESPACE"
else
    echo -e "✅ Namespace '$NAMESPACE' already exists."
fi

echo -e "\n🔹 \033[1;34mDeleting existing Boskos resources...\033[0m"
kubectl delete -f boskos/ --ignore-not-found=true

echo -e "\n🔹 \033[1;34mUpdating $CONFIGMAP_FILE with new config name: $CONFIG_NAME\033[0m"
cat <<EOF > "$CONFIGMAP_FILE"
apiVersion: v1
kind: ConfigMap
metadata:
  name: resources
  namespace: $NAMESPACE
data:
  boskos-resources.yaml: |
    resources:
      - type: "vpc-service"
        state: free
        names:
          - "$CONFIG_NAME"
EOF

echo -e "\n🔹 \033[1;34mApplying Boskos configuration...\033[0m"
kubectl apply -f boskos/

echo -e "\n⏳ \033[1;33mWaiting for resources to become ready...\033[0m"

start_time=$(date +%s)
while true; do
    # Check the status of resources
    PODS_NOT_READY=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep -v 'Running' || true)
    CLUSTER_SECRET_READY=$(kubectl get clustersecretstore -n "$NAMESPACE" --no-headers | awk '{print $5}')
    CLUSTER_SECRET_STATUS=$(kubectl get clustersecretstore -n "$NAMESPACE" --no-headers | awk '{print $3}')
    EXTERNAL_SECRET_READY=$(kubectl get externalsecrets -n "$NAMESPACE" --no-headers | awk '{print $5}')
    EXTERNAL_SECRET_STATUS=$(kubectl get externalsecrets -n "$NAMESPACE" --no-headers | awk '{print $4}')

    NOT_READY_RESOURCES=()
    if [[ -n "$PODS_NOT_READY" ]]; then NOT_READY_RESOURCES+=("Pods"); fi
    if [[ "$CLUSTER_SECRET_READY" != "True" || "$CLUSTER_SECRET_STATUS" != "Valid" ]]; then NOT_READY_RESOURCES+=("ClusterSecretStore"); fi
    if [[ "$EXTERNAL_SECRET_READY" != "True" || "$EXTERNAL_SECRET_STATUS" != "SecretSynced" ]]; then NOT_READY_RESOURCES+=("ExternalSecrets"); fi

    # If all resources are ready, exit the loop
    if [ ${#NOT_READY_RESOURCES[@]} -eq 0 ]; then
        echo -e "\n✅ \033[1;32mAll resources are ready!\033[0m"
        break
    fi

    # Check for timeout
    current_time=$(date +%s)
    elapsed_time=$((current_time - start_time))
    if [ "$elapsed_time" -ge "$MAX_WAIT" ]; then
        echo -e "\n⏳ \033[1;31mTimeout: Some resources are still not ready after $MAX_WAIT seconds.\033[0m"
        break
    fi

    # Display progress and wait before checking again
    echo -ne "\r⏳ Waiting... Resources not ready: ${NOT_READY_RESOURCES[*]}     "
    sleep "$INTERVAL"
done

# Show final status
echo -e "\n\n🔹 \033[1;34mFinal Resource Status:\033[0m"
kubectl get pods,clustersecretstore,externalsecrets -n "$NAMESPACE" --no-headers | column -t
