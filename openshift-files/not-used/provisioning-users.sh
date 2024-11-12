#!/bin/bash

# Keycloak settings
KEYCLOAK_URL="https://keycloak-keycloak.apps.your-cluster-domain.com"
KEYCLOAK_REALM="your-realm"
KEYCLOAK_CLIENT_ID="your-client-id"
KEYCLOAK_CLIENT_SECRET="your-client-secret"
KEYCLOAK_ADMIN_USERNAME="admin"
KEYCLOAK_ADMIN_PASSWORD="admin-password"

# OpenShift settings
OPENSHIFT_API_URL="https://api.your-cluster-domain.com:6443"
OPENSHIFT_TOKEN="your-openshift-token"

# User settings
USER_PREFIX="student"
USER_PASSWORD="ibmrhocp"
START_NUMBER=1
END_NUMBER=30

# Get Keycloak access token
get_keycloak_token() {
    curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
         -H "Content-Type: application/x-www-form-urlencoded" \
         -d "grant_type=password&client_id=admin-cli&username=${KEYCLOAK_ADMIN_USERNAME}&password=${KEYCLOAK_ADMIN_PASSWORD}" | jq -r '.access_token'
}

KEYCLOAK_TOKEN=$(get_keycloak_token)

# Create Keycloak group
create_keycloak_group() {
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/groups" \
         -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" \
         -H "Content-Type: application/json" \
         -d '{"name": "students"}'
}

GROUP_ID=$(create_keycloak_group | jq -r '.id')

# Create Keycloak user and add to group
create_keycloak_user() {
    local username=$1
    local password=$2
    
    # Create user
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users" \
         -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" \
         -H "Content-Type: application/json" \
         -d "{\"username\":\"${username}\",\"enabled\":true,\"credentials\":[{\"type\":\"password\",\"value\":\"${password}\",\"temporary\":false}]}"
    
    # Get user ID
    local user_id=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users?username=${username}" \
                    -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" | jq -r '.[0].id')
    
    # Add user to group
    curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users/${user_id}/groups/${GROUP_ID}" \
         -H "Authorization: Bearer ${KEYCLOAK_TOKEN}"
}

# Create OpenShift RoleBinding
create_openshift_rolebinding() {
    local username=$1
    local namespace=$1
    
    # Check if namespace exists before creating
    if ! oc --token="${OPENSHIFT_TOKEN}" --server="${OPENSHIFT_API_URL}" get namespace ${namespace} &>/dev/null; then
        oc --token="${OPENSHIFT_TOKEN}" --server="${OPENSHIFT_API_URL}" create namespace ${namespace}
    fi
    
    oc --token="${OPENSHIFT_TOKEN}" --server="${OPENSHIFT_API_URL}" apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: namespace-admin-binding
  namespace: ${namespace}
subjects:
- kind: User
  name: ${username}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: namespace-admin
  apiGroup: rbac.authorization.k8s.io
EOF
}

# Main execution
for i in $(seq -f "%02g" ${START_NUMBER} ${END_NUMBER})
do
    username="${USER_PREFIX}${i}"
    
    echo "Processing user ${username}"
    create_keycloak_user "${username}" "${USER_PASSWORD}"
    create_openshift_rolebinding "${username}"
done

echo "User provisioning complete"