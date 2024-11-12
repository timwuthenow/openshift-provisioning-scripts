#!/bin/bash

# Function to create or update a resource
create_or_update_resource() {
    local resource_file=$1
    local resource_type=$(grep -m1 'kind:' "$resource_file" | awk '{print tolower($2)}')
    local resource_name=$(grep -m1 'name:' "$resource_file" | awk '{print $2}')

    if oc get $resource_type $resource_name &>/dev/null; then
        echo "Updating existing $resource_type: $resource_name"
        oc apply -f "$resource_file"
    else
        echo "Creating new $resource_type: $resource_name"
        oc create -f "$resource_file"
    fi
}

# Prompt for OpenShift developer instance
read -p "Is this an OpenShift developer instance? (yes/no): " is_openshift_dev

if [[ $is_openshift_dev == "yes" ]]; then
    read -p "Enter your Red Hat username: " rh_username
    namespace="${rh_username}-dev"
    echo "Using namespace: $namespace"
else
    read -p "Enter the project name (default: keycloak): " project_name
    namespace=${project_name:-keycloak}
    if oc get project $namespace &>/dev/null; then
        echo "Using existing project: $namespace"
    else
        echo "Creating new project: $namespace"
        oc new-project $namespace
    fi
fi

# Set the project context
oc project $namespace

# Deploy PostgreSQL 16 for Keycloak
echo "Running admin command"
if ! oc adm policy add-scc-to-user anyuid -z default -n $namespace; then
    echo "Warning: Unable to add SCC 'anyuid' to the default service account. You may need elevated permissions."
fi

create_or_update_resource postgres-pvc.yaml
create_or_update_resource postgres-dep.yaml
create_or_update_resource postgres-svc.yaml

# Fix the postgres-route.yaml file
sed -i '' 's/^  //' postgres-route.yaml
create_or_update_resource postgres-route.yaml

echo "Completed Postgres setup"

# Wait for PostgreSQL to be ready
oc rollout status deployment/postgresql

# Deploy Keycloak
echo "Deploying Keycloak"

create_or_update_resource keycloak-pvc.yaml
create_or_update_resource keycloak-dep.yaml
create_or_update_resource keycloak-svc.yaml
create_or_update_resource keycloak-route.yaml

# Wait for Keycloak to be ready
oc rollout status deployment/keycloak

# Get the Keycloak URL
KEYCLOAK_URL=$(oc get route keycloak -o jsonpath='{.spec.host}')

# Configure OpenShift for Keycloak OIDC (this step requires manual intervention in Keycloak UI)
echo "Please follow these steps manually in the Keycloak UI:"
echo "1. Log in to Keycloak admin console at https://$KEYCLOAK_URL/auth/admin with username 'admin' and password 'admin'"
echo "2. Create a new realm called 'openshift'"
echo "3. In the 'openshift' realm, create a new client with:"
echo "   - Client ID: openshift"
echo "   - Client Protocol: openid-connect"
echo "   - Access Type: confidential"
echo "   - Valid Redirect URIs: https://oauth-openshift.apps.<cluster_domain>/oauth2callback/keycloak"
echo "4. After saving, go to the 'Credentials' tab for this client and copy the Secret"
echo "5. Create users student01 through student30 with password 'ibmrhocp' for each"

read -p "Press enter when you have completed these steps and have the client secret ready"

# Configure OpenShift for Keycloak OIDC
read -p "Enter the client secret from Keycloak: " CLIENT_SECRET

echo "Script execution completed."