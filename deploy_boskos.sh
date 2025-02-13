#!/bin/bash

set -e  # Exit on error

# Validate input
if [ -z "$1" ]; then
  echo "Usage: $0 <config-name>"
  exit 1
fi

CONFIG_NAME=$1
NAMESPACE="test-pods"
CONFIG_FILE="boskos/boskos-configmap.yaml"

# Ensure namespace exists
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "Namespace $NAMESPACE does not exist. Creating..."
  kubectl create namespace "$NAMESPACE"
else
  echo "Namespace $NAMESPACE already exists."
fi

# Delete existing Boskos resources
echo "Deleting existing Boskos resources..."
kubectl delete -f boskos/ --ignore-not-found=true

# Modify boskos-configmap.yaml to update only the names field
echo "Updating $CONFIG_FILE with the new config name: $CONFIG_NAME"

# Use sed to properly replace names under vpc-service
awk -v name="$CONFIG_NAME" '
    BEGIN { in_block=0 }
    /- type: "vpc-service"/ { print; in_block=1; next }
    in_block && /names:/ { print "        names:\n          - \"" name "\""; in_block=0; next }
    in_block && /^        -/ { next }  # Remove old names
    { print }
' "$CONFIG_FILE" > temp.yaml && mv temp.yaml "$CONFIG_FILE"

# Ensure the names field exists
if ! grep -q "names:" "$CONFIG_FILE"; then
  sed -i '/- type: "vpc-service"/a\        names:\n          - "'$CONFIG_NAME'"' "$CONFIG_FILE"
fi

# Deploy Boskos resources
echo "Applying Boskos configuration..."
kubectl apply -f boskos/

# Wait for resources to be ready
sleep 5

# Display deployed resources
echo "Fetching deployed resources in namespace: $NAMESPACE"
echo "-----------------------------------------------------"
echo "🔹 **Pods:**"
kubectl get all -n "$NAMESPACE"
echo "-----------------------------------------------------"
echo "🔹 **ClusterSecretStore:**"
kubectl get clustersecretstore -n "$NAMESPACE" || echo "No ClusterSecretStore found."
echo "-----------------------------------------------------"
echo "🔹 **ExternalSecrets:**"
kubectl get externalsecrets -n "$NAMESPACE" || echo "No ExternalSecrets found."
echo "-----------------------------------------------------"

echo "✅ Boskos deployment completed successfully!"
