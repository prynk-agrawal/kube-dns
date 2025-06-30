#!/bin/bash

NAMESPACE="default" # Ensure this matches your deployment's namespace
DEPLOYMENT_NAME="ubuntu-dnspyre-test" # Name of your dnspyre deployment
CONCURRENCY=1000    # Number of concurrent queries. Adjust as needed to induce load.
TEST_DURATION="5m"  # Duration for the load test (e.g., 1m, 5m, 10m)
LOG_FILE="dnspyre_load_test_results.log"

echo "--- Generating DNS Load ---"

# 1. Get the kube-dns service IP
KUBE_DNS_IP=$(kubectl get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}')
if [ -z "$KUBE_DNS_IP" ]; then
    echo "Error: Could not find kube-dns ClusterIP. Exiting."
    exit 1
fi
echo "Identified kube-dns ClusterIP: $KUBE_DNS_IP"

# 2. Get the name of one of the dnspyre test runner pods
# We'll pick the first available pod for execution
POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT_NAME} -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD_NAME" ]; then
    echo "Error: Could not find any running pods for deployment ${DEPLOYMENT_NAME}. Please ensure the deployment is ready."
    exit 1
fi
echo "Using pod: $POD_NAME to generate DNS load."

# 3. Execute dnspyre command inside the pod
echo "Running dnspyre with concurrency $CONCURRENCY for $TEST_DURATION against $KUBE_DNS_IP..."
echo "Results will be logged to $LOG_FILE inside the pod."

# The dnspyre command to execute inside the pod
# We use bash -c to run the full command string
# Note: The `dnspyre` binary is expected to be in the container's PATH.
# The `/app-services-fqdn.txt` is the path where the file was copied.
kubectl exec -it "${POD_NAME}" -n "${NAMESPACE}" -- bash -c "PATH=\"\$PATH:/root/go/bin/\" dnspyre -s \"${KUBE_DNS_IP}\" @/app-services-fqdn.txt -c ${CONCURRENCY} --duration=${TEST_DURATION} --log-requests --log-requests-path \"${LOG_FILE}\"" || { echo "ERROR: dnspyre command failed inside the pod."; exit 1; }

echo "--- DNS Load Generation Complete ---"
echo "Results are saved in '/$LOG_FILE' inside pod '$POD_NAME'."
echo "You can retrieve the log file using: "
echo "kubectl cp ${NAMESPACE}/${POD_NAME}:/${LOG_FILE} ./${LOG_FILE}"
echo ""
echo "To view the results directly in the pod:"
echo "kubectl exec -it ${POD_NAME} -n ${NAMESPACE} -- cat /${LOG_FILE}"
echo "To filter errors:"
echo "kubectl exec -it ${POD_NAME} -n ${NAMESPACE} -- grep -E \"status: SERVFAIL|timeout\" /${LOG_FILE}"
