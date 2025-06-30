#!/bin/bash

# --- Configuration ---
NUM_SERVICES=500
NAMESPACE="default" # Change this if you want to create resources in a different namespace
TEMP_YAML_FILE="/tmp/dns-test-resources.yaml"
FQDN_LIST_FILE="internal-dns-names.txt"
BASE_SERVICE_NAME="test-svc-" # Base name for your services and deployments

# --- Script Start ---
echo "Starting creation of $NUM_SERVICES services and deployments in namespace '$NAMESPACE'..."

# Clear previous FQDN list file and temporary YAML file
> "$FQDN_LIST_FILE"
> "$TEMP_YAML_FILE"

# Loop to generate YAML content and FQDN list
for i in $(seq 1 $NUM_SERVICES); do
  SERVICE_NAME="${BASE_SERVICE_NAME}$i"
  # Using a slightly different name for deployment to avoid potential conflicts if base_service_name is reused
  DEPLOYMENT_NAME="${BASE_SERVICE_NAME}dep-$i" 

  # Append Deployment YAML to the temporary file
  cat <<EOF >> "$TEMP_YAML_FILE"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT_NAME
  namespace: $NAMESPACE
  labels:
    app: $SERVICE_NAME # Service will select based on this label
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $SERVICE_NAME
  template:
    metadata:
      labels:
        app: $SERVICE_NAME
    spec:
      containers:
      - name: nginx
        image: nginx:alpine # A small, lightweight image
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: $SERVICE_NAME
  namespace: $NAMESPACE
spec:
  selector:
    app: $SERVICE_NAME # Selector matches deployment's label
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: ClusterIP # Standard service type for internal communication
EOF

  # Append the Fully Qualified Domain Name (FQDN) to the list file
  echo "$SERVICE_NAME.$NAMESPACE.svc.cluster.local" >> "$FQDN_LIST_FILE"
done

echo "Generated YAML manifests for $NUM_SERVICES resources in '$TEMP_YAML_FILE'."
echo "Generated list of FQDNs in '$FQDN_LIST_FILE'."

# Apply all resources at once for efficiency
echo "Applying resources to Kubernetes cluster using 'kubectl apply'. This might take a while..."
kubectl apply -f "$TEMP_YAML_FILE"
echo "Resource application complete."

echo ""
echo "You can now use '$FQDN_LIST_FILE' for your DNS testing with tools like dnspyre."
echo ""
echo "--- IMPORTANT: CLEANUP COMMANDS ---"
echo "To delete all $NUM_SERVICES Deployments and Services created by this script, run:"
echo "for i in \$(seq 1 $NUM_SERVICES); do kubectl delete deployment ${BASE_SERVICE_NAME}dep-\$i -n $NAMESPACE; kubectl delete service ${BASE_SERVICE_NAME}\$i -n $NAMESPACE; done"
echo "Then, to clean up the local files created by this script, run:"
echo "rm -f $TEMP_YAML_FILE $FQDN_LIST_FILE"
echo "-----------------------------------"
