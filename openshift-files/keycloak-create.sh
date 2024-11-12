#!/bin/bash

# Prompt for OpenShift developer instance
read -p "Is this an OpenShift developer instance? (yes/no): " is_openshift_dev

if [[ $is_openshift_dev == "yes" ]]; then
    read -p "Enter your Red Hat username: " rh_username
    namespace="${rh_username}-dev"
    echo "Using namespace: $namespace"
else
    read -p "Enter the project name (default: keycloak): " project_name
    namespace=${project_name:-keycloak}
    echo "Creating new project: $namespace"
    oc new-project $namespace

    # Set the project context
    oc project $namespace
    
    # Deploy PostgreSQL 16 for Keycloak
    echo "Running admin command"
    oc adm policy add-scc-to-user anyuid -z default -n $namespace
fi

# Set the project context
oc project $namespace

echo "Creating the Postgres Instance for Keycloak"

echo "Creating PVC"
oc create -f postgres-pvc.yaml
echo "Creating deployment"
oc create -f postgres-dep.yaml
echo "Creating service"
oc create -f postgres-svc.yaml
sed -i 's/^\s*-/-/' postgres-route.yaml
echo "Creating route"
oc create -f postgres-route.yaml

echo "Completed Postgres"

# Wait for PostgreSQL to be ready
oc rollout status deployment/postgresql

# Deploy Keycloak
echo "Deploying Keycloak"

oc create -f keycloak-pvc.yaml
oc create -f keycloak-dep.yaml
oc create -f keycloak-svc.yaml
oc create -f keycloak-route.yaml

# Wait for Keycloak to be ready
oc rollout status deployment/keycloak

# Get the Keycloak URL
KEYCLOAK_URL=$(oc get route keycloak -o jsonpath='{.spec.host}')

# Create users and link them to namespaces
for i in $(seq -w 1 30)
do
  oc create namespace student$i-namespace
  # Create RoleBinding
  oc create rolebinding student$i-admin --clusterrole=admin --user=student$i -n student$i-namespace
done

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
oc create secret generic keycloak-oidc-secret --from-literal=clientSecret=$CLIENT_SECRET -n openshift-config

cat <<EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: keycloak
    mappingMethod: claim
    type: OpenID
    openID:
      clientID: openshift
      clientSecret:
        name: keycloak-oidc-secret
      claims:
        preferredUsername:
        - preferred_username
        name:
        - name
        email:
        - email
      issuer: https://$KEYCLOAK_URL/auth/realms/openshift
EOF

# Restart the OpenShift OAuth server to apply changes
oc delete pod -n openshift-authentication -l app=oauth-openshift

echo "Script execution completed."