#!/bin/bash

# Define deployment details
DEPLOYMENT_NAME="dnspyre-test-runner" # Changed name to reflect the image
CONTAINER_NAME="dnspyre-container"
NAMESPACE="default" # Ensure this matches the namespace where your services are created
REPLICAS=2          # Number of replicas
CPU_REQUEST="500m"  # 0.5 CPU core
MEM_REQUEST="1Gi"   # 1 Gigabyte

echo "--- Creating Deployment '$DEPLOYMENT_NAME' with $REPLICAS replicas using dnspyre image ---"

# Create the Deployment YAML and apply it
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEPLOYMENT_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${DEPLOYMENT_NAME}
spec:
  replicas: ${REPLICAS}
  selector:
    matchLabels:
      app: ${DEPLOYMENT_NAME}
  template:
    metadata:
      labels:
        app: ${DEPLOYMENT_NAME}
    spec:
      containers:
      - name: ${CONTAINER_NAME}
        image: tantalor93/dnspyre:latest # <--- Changed to dnspyre image
        command: ["sleep", "infinity"]    # <--- Override command to keep container running
        stdin: true
        tty: true
        resources:
          requests:
            cpu: "${CPU_REQUEST}"
            memory: "${MEM_REQUEST}"
          limits:
            cpu: "${CPU_REQUEST}"
            memory: "${MEM_REQUEST}"
EOF

echo "--- Waiting for Deployment '$DEPLOYMENT_NAME' to be ready ---"
kubectl wait --for=condition=Available deployment/${DEPLOYMENT_NAME} --timeout=300s -n ${NAMESPACE} || { echo "Deployment failed to become ready."; exit 1; }

# Get the names of all pods created by this Deployment
POD_NAMES=$(kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT_NAME} -o jsonpath='{.items[*].metadata.name}')

if [ -z "$POD_NAMES" ]; then
    echo "Error: Could not find any pods for deployment ${DEPLOYMENT_NAME}. Exiting."
    exit 1
fi

echo "--- Found pods: $POD_NAMES ---"

# Loop through each pod to copy the file
for POD_NAME in $POD_NAMES; do
    echo "--- Processing pod: $POD_NAME ---"

    # Removed the dnspyre installation steps as it's now in the image

    echo "--- Copying 'internal-dns-names.txt' into pod '$POD_NAME' ---"
    # Copy the file from your local machine (where this script is running) into the pod
    # Assumes 'internal-dns-names.txt' is in the current directory on your local machine
    kubectl cp internal-dns-names.txt "${NAMESPACE}/${POD_NAME}:/internal-dns-names.txt" || { echo "WARNING: Failed to copy internal-dns-names.txt to pod '$POD_NAME'. Continuing with next pod."; continue; } # Use continue

done

echo "------------------------------------------------------------------"
echo "Deployment '$DEPLOYMENT_NAME' with $REPLICAS replicas is ready using dnspyre image."
echo "File '/internal-dns-names.txt' has been copied to all active pods."
echo "You can now attach to any of the pods to run tests: "
echo "kubectl attach -it $(echo $POD_NAMES | awk '{print $1}') -n ${NAMESPACE}"
echo "Or list pods to pick one: kubectl get pods -l app=${DEPLOYMENT_NAME} -n ${NAMESPACE}"
echo "------------------------------------------------------------------"
