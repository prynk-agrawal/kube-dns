#!/bin/bash

# Define deployment details
DEPLOYMENT_NAME="ubuntu-dnspyre-test"
CONTAINER_NAME="ubuntu-dnspyre-container"
NAMESPACE="default" # Ensure this matches the namespace where your services are created
CPU_REQUEST="500m"  # 0.5 CPU core
MEM_REQUEST="1Gi"   # 1 Gigabyte

echo "--- Creating Ubuntu Deployment '$DEPLOYMENT_NAME' ---"

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
  replicas: 1 # You can set this to more if you need multiple test runners
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
        image: ubuntu:latest
        command: ["/bin/bash", "-c", "sleep infinity"] # Keeps the container running
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

# Get the name of the actual pod created by the Deployment
# We assume there's at least one pod and pick the first one
POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT_NAME} -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD_NAME" ]; then
    echo "Error: Could not find pod for deployment ${DEPLOYMENT_NAME}."
    exit 1
fi

echo "--- Found pod: $POD_NAME ---"

echo "--- Installing dnspyre inside pod '$POD_NAME' ---"
# Install necessary packages and dnspyre
# The 'bash -c' is used to execute multiple commands as a single string
kubectl exec -it "${POD_NAME}" -n "${NAMESPACE}" -- bash -c " \
    export DEBIAN_FRONTEND=noninteractive && \
    apt update && \
    apt install -y golang git wget unzip && \
    go install github.com/tantalor93/dnspyre/v3@latest && \
    export PATH=\"\$PATH:/root/go/bin/\" && \
    echo 'dnspyre installation complete and PATH updated.' \
" || { echo "Failed to install dnspyre in pod."; exit 1; }

echo "--- Copying 'internal-dns-names.txt' into pod '$POD_NAME' ---"
# Copy the file from your local machine (where this script runs) into the pod
# Assumes 'internal-dns-names.txt' is in the current directory on your local machine
kubectl cp internal-dns-names.txt "${NAMESPACE}/${POD_NAME}:/internal-dns-names.txt" || { echo "Failed to copy internal-dns-names.txt."; exit 1; }

echo "------------------------------------------------------------------"
echo "Ubuntu Deployment '$DEPLOYMENT_NAME' is ready."
echo "dnspyre is installed in pod '$POD_NAME'."
echo "File '/internal-dns-names.txt' has been copied to pod '$POD_NAME'."
echo "You can now attach to the pod to run tests: "
echo "kubectl attach -it ${POD_NAME} -n ${NAMESPACE}"
echo "------------------------------------------------------------------"
