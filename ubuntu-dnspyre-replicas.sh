#!/bin/bash

# Define deployment details
DEPLOYMENT_NAME="ubuntu-dnspyre-test"
CONTAINER_NAME="ubuntu-dnspyre-container"
NAMESPACE="default" # Ensure this matches the namespace where your services are created
CPU_REQUEST="800m"  # 0.8 CPU core (corrected comment from 0.5)
MEM_REQUEST="2Gi"   # 2 Gigabytes (corrected comment from 1 Gigabyte)
NUM_REPLICAS=2      # Explicitly state the number of replicas

# --- IMPORTANT: Align with the FQDN_LIST_FILE from the previous script ---
FQDN_LIST_FILE="app-services-fqdn.txt" # This must match the output file from the service creation script

echo "--- Creating Ubuntu Deployment '$DEPLOYMENT_NAME' with $NUM_REPLICAS replicas ---"

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
  replicas: ${NUM_REPLICAS} # Now using the variable
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
# Wait for all replicas to be available
kubectl wait --for=condition=Available deployment/${DEPLOYMENT_NAME} --timeout=300s -n ${NAMESPACE} || { echo "Deployment failed to become ready."; exit 1; }

# Get the names of all pods created by the Deployment
# We now get all names and iterate
POD_NAMES=$(kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT_NAME} -o jsonpath='{.items[*].metadata.name}')

if [ -z "$POD_NAMES" ]; then
    echo "Error: Could not find any pods for deployment ${DEPLOYMENT_NAME}."
    exit 1
fi

echo "--- Found pods: ${POD_NAMES} ---"

# Loop through each pod to install dnspyre and copy the FQDN file
for POD_NAME in ${POD_NAMES}; do
    echo "--- Installing dnspyre inside pod '$POD_NAME' ---"
    # Install necessary packages and dnspyre
    kubectl exec -it "${POD_NAME}" -n "${NAMESPACE}" -- bash -c " \
        export DEBIAN_FRONTEND=noninteractive && \
        apt update && \
        apt install -y golang git wget unzip && \
        go install github.com/tantalor93/dnspyre/v3@latest && \
        export PATH=\"\$PATH:/root/go/bin/\" && \
        echo 'dnspyre installation complete and PATH updated.' \
    " || { echo "Failed to install dnspyre in pod '${POD_NAME}'."; continue; } # Continue to next pod if one fails

    echo "--- Copying '${FQDN_LIST_FILE}' into pod '$POD_NAME' ---"
    # Copy the FQDN list file from your local machine into the pod
    kubectl cp "${FQDN_LIST_FILE}" "${NAMESPACE}/${POD_NAME}:/${FQDN_LIST_FILE}" || { echo "Failed to copy ${FQDN_LIST_FILE} to pod '${POD_NAME}'."; continue; } # Continue to next pod if one fails
done

echo "------------------------------------------------------------------"
echo "Ubuntu Deployment '$DEPLOYMENT_NAME' is ready with $NUM_REPLICAS pods."
echo "dnspyre is installed in all pods."
echo "File '/${FQDN_LIST_FILE}' has been copied to all pods."
echo "You can now attach to individual pods to run tests:"
echo "Example: kubectl attach -it ${POD_NAMES// / -n ${NAMESPACE} || kubectl attach -it } -n ${NAMESPACE}" # This is a bit hacky to show all, but gives a hint
echo "Alternatively, get the list of pods with: kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT_NAME}"
echo "Then use: kubectl attach -it <specific-pod-name> -n ${NAMESPACE}"
echo "------------------------------------------------------------------"
