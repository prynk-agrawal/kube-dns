#!/bin/bash

# --- Configuration ---
# Now, NUM_SERVICES will be the total number of *only* services created.
# The concept of "dummy entries" is merged, as all will be FQDN-only services.
TOTAL_FQDN_SERVICES=2200 # Total number of Services to create
NAMESPACE="default"      # The Kubernetes namespace where resources will be created
BASE_APP_NAME="test"     # Base name for your services (e.g., test-svc-001)
FQDN_LIST_FILE="app-services-fqdn.txt" # File to store the generated FQDNs

echo "--- Preparing to create $TOTAL_FQDN_SERVICES Services (FQDN only, no Deployments) ---"
echo "Resources will be created in namespace: $NAMESPACE"

# Clear previous FQDN list file if it exists
> "$FQDN_LIST_FILE"

# --- Loop to create Services directly (no backing Deployments) ---
for i in $(seq 1 $TOTAL_FQDN_SERVICES); do
  # Pad the number with leading zeros for consistent naming (e.g., 0001, 0010, 0100, 1000)
  # Using %04d to accommodate up to 4 digits for 2200 services.
  SVC_NUMBER=$(printf "%04d" "$i")
  SERVICE_NAME="${BASE_APP_NAME}-svc-${SVC_NUMBER}"

  echo "Creating Service '$SERVICE_NAME' (no backing Deployment)..."

  # Create Service directly by piping YAML to kubectl apply
  # IMPORTANT: The selector here should *not* match any existing deployment's labels
  # It's set to a unique, non-matching label to ensure no pods back this service.
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: "$SERVICE_NAME"
  namespace: "$NAMESPACE"
spec:
  # This selector ensures the service will not find any backing pods,
  # thus acting purely as a DNS entry.
  selector:
    app: "no-pods-here-${SERVICE_NAME}" # Unique, non-matching selector
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80 # TargetPort still needed even without pods
  type: ClusterIP
EOF

  # Append the FQDN to the list file
  echo "${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local" >> "$FQDN_LIST_FILE"
done

echo "--- Resource creation initiated ---"
echo "Successfully created $TOTAL_FQDN_SERVICES Services (FQDN only, no backing Deployments)."
echo "Generated '$FQDN_LIST_FILE' with FQDNs for all $TOTAL_FQDN_SERVICES services."

echo ""
echo "--- Cleanup Commands (IMPORTANT!) ---"
echo "To delete all created Services:"
echo "for i in \$(seq 1 $TOTAL_FQDN_SERVICES); do \\"
echo "  SVC_NUMBER=\$(printf \"%04d\" \"\$i\"); \\"
echo "  kubectl delete service \"${BASE_APP_NAME}-svc-\${SVC_NUMBER}\" -n \"$NAMESPACE\" --ignore-not-found=true; \\"
echo "done"
echo "To remove the local FQDN list file: rm \"$FQDN_LIST_FILE\""
echo "-----------------------------------"
