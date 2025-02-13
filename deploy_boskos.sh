#!/bin/bash

set -e  # Exit on error

# Function to check if resources are ready
check_resources_ready() {
    # Check deployment status (looking for 1/1 replicas)
    deployments=$(kubectl get deployments -n test-pods --no-headers)
    not_ready_deployments=$(echo "$deployments" | grep -v "1/1" | wc -l)

    # Check if ClusterSecretStore is ready
    clustersecretstore_status=$(kubectl get clustersecretstore -n test-pods -o custom-columns=":status.ready" | grep -v "True" | wc -l)

    # If there are any resources not ready, return 1 (false)
    if [ "$not_ready_deployments" -gt 0 ] || [ "$clustersecretstore_status" -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# Function to print the table format for the resource status
print_resource_status() {
    echo "🔹 Current Resource Status:"
    echo "-----------------------------------------------------"
    echo "🔹 **Pods:**"
    kubectl get pods -n test-pods --no-headers | awk '{print "NAME:", $1, "\t READY:", $2, "\t STATUS:", $3, "\t RESTARTS:", $4, "\t AGE:", $5}'
    echo "-----------------------------------------------------"

    echo "🔹 **Deployments:**"
    kubectl get deployments -n test-pods --no-headers | awk '{print "NAME:", $1, "\t READY:", $2, "\t UP-TO-DATE:", $3, "\t AVAILABLE:", $4, "\t AGE:", $5}'
    echo "-----------------------------------------------------"

    echo "🔹 **Services:**"
    kubectl get services -n test-pods --no-headers | awk '{print "NAME:", $1, "\t TYPE:", $2, "\t CLUSTER-IP:", $3, "\t EXTERNAL-IP:", $4, "\t PORT(S):", $5, "\t AGE:", $6}'
    echo "-----------------------------------------------------"

    echo "🔹 **ReplicaSets:**"
    kubectl get replicasets -n test-pods --no-headers | awk '{print "NAME:", $1, "\t DESIRED:", $2, "\t CURRENT:", $3, "\t READY:", $4, "\t AGE:", $5}'
    echo "-----------------------------------------------------"

    echo "🔹 **ClusterSecretStore:**"
    kubectl get clustersecretstore -n test-pods --no-headers | awk '{print "NAME:", $1, "\t AGE:", $2, "\t STATUS:", $3, "\t CAPABILITIES:", $4, "\t READY:", $5}'
    echo "-----------------------------------------------------"

    echo "🔹 **ExternalSecrets:**"
    kubectl get externalsecrets -n test-pods --no-headers | awk '{print "NAME:", $1, "\t STORE:", $2, "\t REFRESH INTERVAL:", $3, "\t STATUS:", $4, "\t READY:", $5}'
    echo "-----------------------------------------------------"
}

# Step 1: Check if the namespace 'test-pods' exists
echo "🔹 Checking if namespace 'test-pods' exists..."
kubectl get namespace test-pods &>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Namespace 'test-pods' already exists."
else
    echo "❌ Namespace 'test-pods' does not exist. Creating namespace..."
    kubectl create namespace test-pods
fi

# Step 2: Delete existing Boskos resources if any
echo "🔹 Deleting existing Boskos resources..."
kubectl delete configmap resources -n test-pods &>/dev/null
kubectl delete configmap boskos-config -n test-pods &>/dev/null
kubectl delete clustersecretstore secretstore-ibm -n test-pods &>/dev/null
kubectl delete externalsecret external-secret-janitor -n test-pods &>/dev/null
kubectl delete deployments boskos-janitor-ibmcloud boskos-reaper boskos -n test-pods &>/dev/null
kubectl delete service boskos -n test-pods &>/dev/null
kubectl delete customresourcedefinition dynamicresourcelifecycles.boskos.k8s.io resources.boskos.k8s.io &>/dev/null
kubectl delete clusterrole boskos &>/dev/null
kubectl delete serviceaccount boskos &>/dev/null
kubectl delete clusterrolebinding boskos &>/dev/null

# Step 3: Update the ConfigMap with the new CONFIG_NAME
CONFIG_NAME=$1  # Assuming the config name is passed as the first argument
if [ -z "$CONFIG_NAME" ]; then
    echo "❌ Error: Config name is required."
    echo "Usage: ./deploy_boskos.sh <config-name>"
    exit 1
fi

echo "🔹 Updating ConfigMap with new config name: $CONFIG_NAME"
kubectl create configmap resources -n test-pods --from-literal=boskos-resources="resources:\n  - type: \"vpc-service\"\n    state: free\n    names:\n      - \"$CONFIG_NAME\"" --dry-run=client -o yaml | kubectl apply -f -

# Step 4: Apply Boskos resources
echo "🔹 Applying Boskos configuration..."
kubectl apply -f boskos/.

# Step 5: Wait for resources to become ready
echo "⏳ Waiting for resources to become ready..."
while true; do
    check_resources_ready
    if [ $? -eq 0 ]; then
        echo "✅ All resources are now ready!"
        break
    else
        echo "⏳ Waiting... Resources are not fully ready yet."
        sleep 5  # Check every 5 seconds
    fi
done

# Step 6: Output current resource status in formatted table
print_resource_status
