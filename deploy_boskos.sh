#!/bin/bash

set -e  # Exit on error

CONFIG_NAME=$1
NAMESPACE="test-pods"
CONFIGMAP_FILE="boskos/boskos-configmap.yaml"

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

# Wait for resources to initialize with a spinner animation
echo -e "\n⏳ \033[1;33mWaiting for resources to initialize...\033[0m"
spin="|/-\\"
i=0
while ps aux | grep -q '[k]ubectl apply'; do
    i=$(( (i+1) %4 )); # Loop through the spinner array
    echo -ne "\r$spin$i"
    sleep 0.1
done
echo -ne "\r✅ Resources initialized!            \n"

# Check the resources status
echo -e "\n🔹 \033[1;34mChecking the resource status...\033[0m"

# Check Pods status
PODS_NOT_READY=$(kubectl get pods -n "$NAMESPACE" --no-headers | awk '$3 != "Running" {print $1}')

# Check ClusterSecretStore status
CLUSTER_SECRET_READY=$(kubectl get clustersecretstore -n "$NAMESPACE" --no-headers | awk '{print $5}')
CLUSTER_SECRET_STATUS=$(kubectl get clustersecretstore -n "$NAMESPACE" --no-headers | awk '{print $3}')

# Check ExternalSecrets status
EXTERNAL_SECRET_READY=$(kubectl get externalsecrets -n "$NAMESPACE" --no-headers | awk '{print $5}')
EXTERNAL_SECRET_STATUS=$(kubectl get externalsecrets -n "$NAMESPACE" --no-headers | awk '{print $4}')

# Set a flag for errors
NOT_READY_RESOURCES=()

# Check readiness
if [[ -n "$PODS_NOT_READY" ]]; then
    NOT_READY_RESOURCES+=("Pods")
fi

if [[ "$CLUSTER_SECRET_READY" != "True" || "$CLUSTER_SECRET_STATUS" != "Valid" ]]; then
    NOT_READY_RESOURCES+=("ClusterSecretStore")
fi

if [[ "$EXTERNAL_SECRET_READY" != "True" || "$EXTERNAL_SECRET_STATUS" != "SecretSynced" ]]; then
    NOT_READY_RESOURCES+=("ExternalSecrets")
fi

# Report status in a table format
echo -e "\n🔹 \033[1;34mResource Status:\033[0m"
if [ ${#NOT_READY_RESOURCES[@]} -gt 0 ]; then
    echo -e "\033[1;31mDeployment completed with errors.\033[0m"
    echo -e "The following resources are not fully running:"
    printf "%-25s %-10s\n" "Resource" "Status"
    printf "%-25s %-10s\n" "---------------------------------" "----------"
    for res in "${NOT_READY_RESOURCES[@]}"; do
        printf "\033[1;31m%-25s %-10s\033[0m\n" "$res" "Not Ready"
    done
    exit 1
else
    echo -e "\033[1;32mAll resources are running successfully!\033[0m"
    printf "%-25s %-10s\n" "Resource" "Status"
    printf "%-25s %-10s\n" "---------------------------------" "----------"
    printf "\033[1;32m%-25s %-10s\033[0m\n" "Pods" "Running"
    printf "\033[1;32m%-25s %-10s\033[0m\n" "ClusterSecretStore" "Valid"
    printf "\033[1;32m%-25s %-10s\033[0m\n" "ExternalSecrets" "Synced"
fi


kubectl get pods,clustersecretstore,externalsecrets -n "$NAMESPACE" --no-headers | column -t
