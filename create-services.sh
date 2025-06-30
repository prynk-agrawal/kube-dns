#!/bin/bash

# --- Configuration ---
NUM_SERVICES=200       # The total number of Deployments and Services to create
NAMESPACE="default"    # The Kubernetes namespace where resources will be created
BASE_APP_NAME="nginx" # Base name for your services (e.g., app-svc-001)
FQDN_LIST_FILE="app-services-fqdn.txt" # File to store the generated FQDNs

# --- IMPORTANT: Resource limits for these 200 test pods ---
# These are set very low to ensure sufficient resources for your dnspyre pod.
NGINX_CPU_REQUEST="5m"  # 5 millicores (0.005 CPU core)
NGINX_MEM_REQUEST="10Mi" # 10 Mebibytes

echo "--- Preparing to create $NUM_SERVICES Deployments and Services directly ---"
echo "Resources will be created in namespace: $NAMESPACE"
echo "Note: Each Deployment's pod will request CPU=${NGINX_CPU_REQUEST} and Memory=${NGINX_MEM_REQUEST}."

# Clear previous FQDN list file if it exists
> "$FQDN_LIST_FILE"

# --- Loop to create resources directly ---
for i in $(seq 1 $NUM_SERVICES); do
  # Pad the number with leading zeros for consistent naming (e.g., 001, 010, 100)
  SVC_NUMBER=$(printf "%03d" "$i")
  SERVICE_NAME="${BASE_APP_NAME}-svc-${SVC_NUMBER}"
  DEPLOYMENT_NAME="${BASE_APP_NAME}-dep-${SVC_NUMBER}"

  echo "Creating Deployment '$DEPLOYMENT_NAME' and Service '$SERVICE_NAME'..."

  # Create Deployment directly by piping YAML to kubectl apply
  kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "$DEPLOYMENT_NAME"
  namespace: "$NAMESPACE"
  labels:
    app: "$SERVICE_NAME"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: "$SERVICE_NAME"
  template:
    metadata:
      labels:
        app: "$SERVICE_NAME"
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources: # <--- ADDED RESOURCES SECTION HERE
          requests:
            cpu: "${NGINX_CPU_REQUEST}"
            memory: "${NGINX_MEM_REQUEST}"
          limits:
            cpu: "${NGINX_CPU_REQUEST}"
            memory: "${NGINX_MEM_REQUEST}"
EOF

  # Create Service directly by piping YAML to kubectl apply
  # (Service YAML does not need resource limits as it's not a running container)
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: "$SERVICE_NAME"
  namespace: "$NAMESPACE"
spec:
  selector:
    app: "$SERVICE_NAME"
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: ClusterIP
EOF

  # Append the FQDN to the list file
  echo "${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local" >> "$FQDN_LIST_FILE"
done

echo "--- Resource creation initiated ---"
echo "Successfully created $NUM_SERVICES Deployments and Services."
echo "Generated '$FQDN_LIST_FILE' with FQDNs for $NUM_SERVICES services."

echo ""
echo "--- Cleanup Commands (IMPORTANT!) ---"
echo "To delete all created Deployments and Services:"
echo "for i in \$(seq 1 $NUM_SERVICES); do \\"
echo "  SVC_NUMBER=\$(printf \"%03d\" \"\$i\"); \\"
echo "  kubectl delete deployment \"${BASE_APP_NAME}-dep-\${SVC_NUMBER}\" -n \"$NAMESPACE\" --ignore-not-found=true; \\"
echo "  kubectl delete service \"${BASE_APP_NAME}-svc--\${SVC_NUMBER}\" -n \"$NAMESPACE\" --ignore-not-found=true; \\"
echo "done"
echo "To remove the local FQDN list file: rm \"$FQDN_LIST_FILE\""
echo "-----------------------------------"
