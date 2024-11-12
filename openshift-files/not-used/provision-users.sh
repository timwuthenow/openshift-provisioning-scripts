#!/bin/bash

# Keycloak settings
KEYCLOAK_URL="https://keycloak-keycloak.apps.j4fxfomh.eastus.aroapp.io/auth"
KEYCLOAK_REALM="openshift"
KEYCLOAK_CLIENT_ID="openshift"
KEYCLOAK_CLIENT_SECRET="EdyapknlaAMciygTJYszKMmkCjfeJTUb"

# OpenShift settings
OPENSHIFT_API_URL="https://api.j4fxfomh.eastus.aroapp.io:6443"
OPENSHIFT_TOKEN="sha256~nhlURjwN-x-PDPo3ih3C08jh_IuLSkFWByuWt3YdfOo"

# User settings
USER_PREFIX="student"
USER_PASSWORD="ibmrhocp"
START_NUMBER=5
END_NUMBER=6  # Extend this as needed for more users

# Function to get Keycloak access token
get_keycloak_token() {
    echo "Getting Keycloak Token"
    response=$(curl -s -k -X POST "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
         -H "Content-Type: application/x-www-form-urlencoded" \
         -d "grant_type=client_credentials&client_id=${KEYCLOAK_CLIENT_ID}&client_secret=${KEYCLOAK_CLIENT_SECRET}")
    
    echo "Full token response: ${response}"
    
    if [[ "${response}" == *"error"* ]] || [[ "${response}" == *"<html>"* ]]; then
        echo "Error retrieving token: ${response}"
        return 1
    fi
    
    token=$(echo "${response}" | jq -r '.access_token')
    if [ -z "${token}" ] || [ "${token}" = "null" ]; then
        echo "Failed to extract token from response"
        return 1
    fi
    echo "Token (first 20 chars): ${token:0:20}..."
    echo "${token}"
}

# Function to check if a user exists
check_user_exists() {
    local username=$1
    echo "Checking if user ${username} exists"
    user_check=$(curl -s -k -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" \
         "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users?username=${username}")
    echo "User check response: ${user_check}"
    if [[ "${user_check}" == *"${username}"* ]]; then
        echo "User ${username} already exists"
        return 0
    fi
    return 1
}

# Function to create Keycloak user
create_keycloak_user() {
    local username=$1
    local password=$2
    
    if check_user_exists "${username}"; then
        return 0
    fi

    echo "Creating user: ${username}"
    response=$(curl -s -k -X POST "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users" \
         -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" \
         -H "Content-Type: application/json" \
         -d "{\"username\":\"${username}\",\"enabled\":true,\"credentials\":[{\"type\":\"password\",\"value\":\"${password}\",\"temporary\":false}]}")
    
    echo "Create user response: ${response}"
    if [[ "${response}" == *"error"* ]] || [[ "${response}" == *"<html>"* ]]; then
        echo "Error creating user: ${response}"
        return 1
    fi
    echo "User ${username} created successfully"
}

# Function to create OpenShift RoleBinding
create_openshift_rolebinding() {
    local username=$1
    local namespace="${username}-namespace"
    
    echo "Creating OpenShift RoleBinding for user: ${username}"
    # Check if namespace exists before creating
    if ! oc --token="${OPENSHIFT_TOKEN}" --server="${OPENSHIFT_API_URL}" get namespace ${namespace} &>/dev/null; then
        oc --token="${OPENSHIFT_TOKEN}" --server="${OPENSHIFT_API_URL}" create namespace ${namespace}
    fi
    
    oc --token="${OPENSHIFT_TOKEN}" --server="${OPENSHIFT_API_URL}" apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${username}-admin-binding
  namespace: ${namespace}
subjects:
- kind: User
  name: ${username}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io
EOF
}

# Main execution
echo "Attempting to get Keycloak token"
KEYCLOAK_TOKEN=$(get_keycloak_token)
if [ -z "${KEYCLOAK_TOKEN}" ]; then
    echo "Failed to retrieve Keycloak token. Exiting."
    exit 1
fi

echo "Token retrieved successfully. Proceeding with user creation."

for i in $(seq -f "%02g" ${START_NUMBER} ${END_NUMBER})
do
    username="${USER_PREFIX}${i}"
    
    echo "Processing user ${username}"
    if create_keycloak_user "${username}" "${USER_PASSWORD}"; then
        create_openshift_rolebinding "${username}"
    else
        echo "Failed to create Keycloak user ${username}. Skipping OpenShift RoleBinding creation."
    fi
done

echo "User provisioning complete"
