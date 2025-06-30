#!/bin/bash

# --- Configuration ---
# Total number of services to create (including what were previously "actual" and "dummy")
TOTAL_SERVICES_TO_CREATE=2000 
NAMESPACE="default"                     # The Kubernetes namespace where resources will be created
BASE_SVC_NAME="svc"                     # Base name for your services (e.g., dns-load-svc-0001)
FQDN_LIST_FILE="app-services-fqdn.txt"  # File to store the generated FQDNs
TEMP_YAML_FILE="temp_services.yaml"     # Temporary file to store all service YAMLs

echo "--- Preparing to create $TOTAL_SERVICES_TO_CREATE Services (FQDN only) ---"
echo "Resources will be created in namespace: $NAMESPACE"

# Clear previous FQDN list file and temporary YAML file if they exist
> "$FQDN_LIST_FILE"
> "$TEMP_YAML_FILE"

echo "--- Generating Service YAML definitions into '$TEMP_YAML_FILE' ---"

# --- Loop to generate all Service YAMLs ---
# Starting service numbering from 1 up to TOTAL_SERVICES_TO_CREATE
for i in $(seq 1 "$TOTAL_SERVICES_TO_CREATE"); do
  # Pad the number with leading zeros for consistent naming (e.g., 0001, 0010, 0100, 1000)
  SVC_NUMBER=$(printf "%04d" "$i")
  SERVICE_NAME="${BASE_SVC_NAME}-${SVC_NUMBER}"

  # Append Service YAML to the temporary file
  cat <<EOF >> "$TEMP_YAML_FILE"
apiVersion: v1
kind: Service
metadata:
  name: "$SERVICE_NAME"
  namespace: "$NAMESPACE"
spec:
  # This selector is deliberately chosen not to match any existing pods,
  # ensuring the service has no backing endpoints.
  selector:
    app: "no-matching-pod-app-${SVC_NUMBER}" # Unique, non-matching selector
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: ClusterIP
---
EOF

  # Append the FQDN to the list file
  echo "${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local" >> "$FQDN_LIST_FILE"
done

echo "--- Applying all Services to Kubernetes via '$TEMP_YAML_FILE' ---"
# Apply all generated services in one go
kubectl apply -f "$TEMP_YAML_FILE" || { echo "ERROR: Failed to apply services."; exit 1; }

echo "--- Resource creation initiated ---"
echo "Successfully created $TOTAL_SERVICES_TO_CREATE Services (FQDN only)."
echo "Generated '$FQDN_LIST_FILE' with FQDNs for all $TOTAL_SERVICES_TO_CREATE services."

echo ""
echo "--- Cleanup Commands (IMPORTANT!) ---"
echo "To delete all created Services:"
echo "for i in \$(seq 1 $TOTAL_SERVICES_TO_CREATE); do \\"
echo "  SVC_NUMBER=\$(printf \"%04d\" \"\$i\"); \\"
echo "  kubectl delete service \"${BASE_SVC_NAME}-\${SVC_NUMBER}\" -n \"$NAMESPACE\" --ignore-not-found=true; \\"
echo "done"
echo "To remove the local FQDN list file: rm \"$FQDN_LIST_FILE\""
echo "To remove the temporary YAML file: rm \"$TEMP_YAML_FILE\""
echo "-----------------------------------"
