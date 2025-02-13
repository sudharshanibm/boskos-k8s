#!/bin/bash

set -e  # Exit script if any command fails

CONFIG_NAME=$1
NAMESPACE="test-pods"
CONFIGMAP_FILE="boskos/boskos-configmap.yaml"

if [ -z "$CONFIG_NAME" ]; then
    echo -e "\033[1;31m❌ Error: Config name parameter is required.\033[0m"
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
i=0
MAX_RETRIES=10
SLEEP_TIME=5

while [ $MAX_RETRIES -gt 0 ]; do
    NOT_READY_RESOURCES=()
    
    PODS_STATUS=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $3}' | grep -Ev 'Running|Completed' || true)
    DEPLOYMENTS_STATUS=$(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $2}' | grep -Ev '1/1|2/2|True' || true)
    CLUSTER_SECRET_STATUS=$(kubectl get clustersecretstore -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $4}' | grep -v 'True' || true)
    EXTERNAL_SECRET_STATUS=$(kubectl get externalsecrets -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $4}' | grep -v 'SecretSynced' || true)

    [[ -n "$PODS_STATUS" ]] && NOT_READY_RESOURCES+=("Pods")
    [[ -n "$DEPLOYMENTS_STATUS" ]] && NOT_READY_RESOURCES+=("Deployments")
    [[ -n "$CLUSTER_SECRET_STATUS" ]] && NOT_READY_RESOURCES+=("ClusterSecretStore")
    [[ -n "$EXTERNAL_SECRET_STATUS" ]] && NOT_READY_RESOURCES+=("ExternalSecrets")

    if [ ${#NOT_READY_RESOURCES[@]} -eq 0 ]; then
        echo -e "\n✅ \033[1;32mAll resources are running successfully!\033[0m"
        break
    fi

    printf "\r⏳ \033[1;33mWaiting... ${spin:i++%${#spin}:1} (${MAX_RETRIES}s left)\033[0m"
    sleep $SLEEP_TIME
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

echo -e "\n🔹 \033[1;34mFetching all resources in namespace: $NAMESPACE\033[0m"
echo -e "\n\033[1;36m-----------------------------------------------------\033[0m"
echo -e "🔹 \033[1;35mPODS:\033[0m"
kubectl get pods -n "$NAMESPACE"
echo -e "\033[1;36m-----------------------------------------------------\033[0m"

echo -e "🔹 \033[1;35mDEPLOYMENTS:\033[0m"
kubectl get deployments -n "$NAMESPACE"
echo -e "\033[1;36m-----------------------------------------------------\033[0m"

echo -e "🔹 \033[1;35mSERVICES:\033[0m"
kubectl get services -n "$NAMESPACE"
echo -e "\033[1;36m-----------------------------------------------------\033[0m"

echo -e "🔹 \033[1;35mREPLICA SETS:\033[0m"
kubectl get replicasets -n "$NAMESPACE"
echo -e "\033[1;36m-----------------------------------------------------\033[0m"

echo -e "🔹 \033[1;35mCLUSTER SECRET STORE:\033[0m"
kubectl get clustersecretstore -n "$NAMESPACE"
echo -e "\033[1;36m-----------------------------------------------------\033[0m"

echo -e "🔹 \033[1;35mEXTERNAL SECRETS:\033[0m"
kubectl get externalsecrets -n "$NAMESPACE"
echo -e "\033[1;36m-----------------------------------------------------\033[0m"

echo -e "\n✅ \033[1;32mBoskos deployment completed successfully!\033[0m 🚀"
