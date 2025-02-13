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

echo -e "\n⏳ \033[1;33mWaiting for resources to become ready...\033[0m"
spin='|/-\'
MAX_RETRIES=30
i=0

# Wait for Pods, ClusterSecretStore, and ExternalSecrets to be ready
while [ $MAX_RETRIES -gt 0 ]; do
    NOT_READY_RESOURCES=()

    PODS_NOT_READY=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | awk '$3 != "Running" && $3 != "Completed" {print $1}')
    CLUSTER_SECRET_READY=$(kubectl get clustersecretstore -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $4}' | grep -wq 'Valid' || echo "Not Ready")
    EXTERNAL_SECRET_READY=$(kubectl get externalsecrets -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $5}' | grep -wq 'True' || echo "Not Ready")

    [[ -n "$PODS_NOT_READY" ]] && NOT_READY_RESOURCES+=("Pods")
    [[ "$CLUSTER_SECRET_READY" == "Not Ready" ]] && NOT_READY_RESOURCES+=("ClusterSecretStore")
    [[ "$EXTERNAL_SECRET_READY" == "Not Ready" ]] && NOT_READY_RESOURCES+=("ExternalSecrets")

    if [ ${#NOT_READY_RESOURCES[@]} -eq 0 ]; then
        echo -e "\n✅ \033[1;32mAll resources are running successfully!\033[0m"
        break
    fi

    printf "\r⏳ \033[1;33mWaiting... ${spin:i++%${#spin}:1} (${MAX_RETRIES}s left)\033[0m"
    sleep 3
    MAX_RETRIES=$((MAX_RETRIES - 1))
done

if [ ${#NOT_READY_RESOURCES[@]} -ne 0 ]; then
    echo -e "\n❌ \033[1;31mDeployment completed with errors.\033[0m"
    echo -e "The following resources are not fully running:"
    for res in "${NOT_READY_RESOURCES[@]}"; do
        echo -e "   - \033[1;31m$res\033[0m"
    done
    exit 1
fi

echo -e "\n✅ \033[1;32mBoskos deployment completed successfully!\033[0m 🚀"

# Function to display resources in formatted color-coded table
display_resources() {
    echo -e "\n🔹 \033[1;34mCurrent Resource Status:\033[0m"
    echo -e "-----------------------------------------------------"

    echo -e "\n🔸 \033[1;36mPods:\033[0m"
    kubectl get pods -n "$NAMESPACE" --no-headers | awk '{ if ($3 == "Running") print "\033[1;32m" $0 "\033[0m"; else print "\033[1;31m" $0 "\033[0m" }'

    echo -e "\n🔸 \033[1;36mDeployments:\033[0m"
    kubectl get deployments -n "$NAMESPACE" --no-headers | awk '{ if ($2 == $3) print "\033[1;32m" $0 "\033[0m"; else print "\033[1;31m" $0 "\033[0m" }'

    echo -e "\n🔸 \033[1;36mServices:\033[0m"
    kubectl get services -n "$NAMESPACE" --no-headers | awk '{ print $0 }'

    echo -e "\n🔸 \033[1;36mReplicaSets:\033[0m"
    kubectl get replicasets -n "$NAMESPACE" --no-headers | awk '{ print $0 }'

    echo -e "\n🔸 \033[1;36mClusterSecretStore:\033[0m"
    kubectl get clustersecretstore -n "$NAMESPACE" --no-headers | awk '{ if ($4 == "Valid") print "\033[1;32m" $0 "\033[0m"; else print "\033[1;31m" $0 "\033[0m" }'

    echo -e "\n🔸 \033[1;36mExternalSecrets:\033[0m"
    kubectl get externalsecrets -n "$NAMESPACE" --no-headers | awk '{ if ($5 == "True") print "\033[1;32m" $0 "\033[0m"; else print "\033[1;31m" $0 "\033[0m" }'
}

# Call the function to display resources
display_resources
