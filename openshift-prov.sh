#!/bin/bash
cd openshift-files
# Function to create namespace and role binding
create_student_namespace() {
    local student_num=$(printf "%02d" $1)
    local namespace="student${student_num}-namespace"
    
    echo "Creating namespace: $namespace"
    oc create namespace $namespace
    
    echo "Creating role binding for: $namespace"
    oc create rolebinding student-admin --clusterrole=admin --serviceaccount=$namespace:default -n $namespace
}

# Main script starts here
echo "Starting Keycloak OpenShift Deployment"

# Create Keycloak project if it doesn't exist
oc new-project keycloak 2>/dev/null || echo "Project keycloak already exists"

# Run admin command
echo "Running admin command"
oc adm policy add-scc-to-user anyuid -z default -n keycloak

# Deploy PostgreSQL
echo "Deploying PostgreSQL"
oc create -f postgresql-pvc.yaml
oc apply -f postgres-dep.yaml
oc create -f postgres-svc.yaml

# Fix for postgres-route.yaml parsing error
sed -i 's/^\s*-/-/' postgres-route.yaml
oc create -f postgres-route.yaml

echo "Completed Postgres"
echo "Waiting for deployment \"postgresql\" rollout to finish..."
oc rollout status deployment/postgresql -n keycloak

# Deploy Keycloak
echo "Deploying Keycloak"
oc create -f keycloak-pvc.yaml
oc create -f keycloak-deployment.yaml
oc create -f keycloak-service.yaml
oc create -f keycloak-route.yaml

echo "Waiting for deployment \"keycloak\" rollout to finish..."
oc rollout status deployment/keycloak -n keycloak

# Create student namespaces
for i in {1..15}
do
    create_student_namespace $i
done

echo "Deployment completed"