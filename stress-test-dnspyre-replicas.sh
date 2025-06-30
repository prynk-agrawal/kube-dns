#!/bin/bash

NAMESPACE="default"             # Ensure this matches your deployment's namespace
DEPLOYMENT_NAME="ubuntu-dnspyre-test" # Name of your dnspyre deployment
CONCURRENCY=1000                # Number of concurrent queries. Adjust as needed to induce load.
TEST_DURATION="5m"              # Duration for the load test (e.g., 1m, 5m, 10m)
LOG_FILE="dnspyre_load_test_results.log" # Name of the log file INSIDE each pod

echo "--- Generating DNS Load ---"

# 1. Get the kube-dns service IP
KUBE_DNS_IP=$(kubectl get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}')
if [ -z "$KUBE_DNS_IP" ]; then
    echo "Error: Could not find kube-dns ClusterIP. Exiting."
    exit 1
fi
echo "Identified kube-dns ClusterIP: $KUBE_DNS_IP"

# 2. Get the names of ALL dnspyre test runner pods
# We now get all names and iterate through them
POD_NAMES=$(kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT_NAME} -o jsonpath='{.items[*].metadata.name}')

if [ -z "$POD_NAMES" ]; then
    echo "Error: Could not find any running pods for deployment ${DEPLOYMENT_NAME}. Please ensure the deployment is ready."
    exit 1
fi
echo "Using pods: ${POD_NAMES} to generate DNS load."

echo "Running dnspyre with concurrency $CONCURRENCY for $TEST_DURATION against $KUBE_DNS_IP on each pod..."
echo "Results will be logged to '/$LOG_FILE' inside each respective pod."

# 3. Loop through each pod and execute the dnspyre command
for POD_NAME in ${POD_NAMES}; do
    echo "--- Starting dnspyre on pod: ${POD_NAME} ---"
    # The dnspyre command to execute inside the pod
    # We use bash -c to run the full command string
    # Note: The `dnspyre` binary is expected to be in the container's PATH.
    # The `/app-services-fqdn.txt` is the path where the file was copied.
    kubectl exec -it "${POD_NAME}" -n "${NAMESPACE}" -- bash -c "PATH=\"\$PATH:/root/go/bin/\" dnspyre -s \"${KUBE_DNS_IP}\" @/app-services-fqdn.txt -c ${CONCURRENCY} --duration=${TEST_DURATION} --log-requests --log-requests-path \"${LOG_FILE}\" --probability=1" &> "/tmp/${POD_NAME}_dnspyre_output.log" &
    # The `&` at the end runs the kubectl exec command in the background,
    # allowing the script to immediately proceed to the next pod.
    # The `&> "/tmp/${POD_NAME}_dnspyre_output.log"` redirects stdout/stderr to a temporary log file locally
    # so we don't spam the console and can debug if a kubectl exec fails.
done

echo "--- All dnspyre instances started in background ---"
echo "Waiting for tests to complete. This will take approximately ${TEST_DURATION} plus some overhead."

# Sleep for the duration of the test plus a small buffer
# This is crucial so the script waits for dnspyre to finish in the background
# We assume TEST_DURATION is in a format parseable by `sleep`
# For example, if TEST_DURATION is "5m", `sleep 5m` works.
# Add 10 seconds buffer for good measure
sleep_duration_seconds=$(echo "$TEST_DURATION" | sed 's/m/*60/g; s/h/*3600/g; s/s//g' | bc)
sleep $((sleep_duration_seconds + 10))

echo "--- DNS Load Generation Complete on all pods ---"
echo "Results for each pod are saved in '/$LOG_FILE' inside the respective pod."
echo "You can retrieve the log file from each pod using commands like:"

for POD_NAME in ${POD_NAMES}; do
    echo "kubectl cp ${NAMESPACE}/${POD_NAME}:/${LOG_FILE} ./${POD_NAME}_${LOG_FILE}"
done

echo ""
echo "To view the results directly in a specific pod (e.g., the first one):"
echo "kubectl exec -it $(echo ${POD_NAMES} | awk '{print $1}') -n ${NAMESPACE} -- cat /${LOG_FILE}"
echo "To filter errors from a specific pod:"
echo "kubectl exec -it $(echo ${POD_NAMES} | awk '{print $1}') -n ${NAMESPACE} -- grep -E \"status: SERVFAIL|timeout\" /${LOG_FILE}"
echo ""
echo "Temporary kubectl exec outputs are in /tmp/ directory on your local machine."
