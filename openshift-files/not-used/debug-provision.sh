#!/bin/bash

# Keycloak settings
KEYCLOAK_URL="https://keycloak-keycloak.apps.j4fxfomh.eastus.aroapp.io/auth"
KEYCLOAK_REALM="openshift"
KEYCLOAK_CLIENT_ID="openshift"
KEYCLOAK_CLIENT_SECRET="EdyapknlaAMciygTJYszKMmkCjfeJTUb"

# User settings
USER_PREFIX="student"
USER_PASSWORD="ibmrhocp"
START_NUMBER=1
END_NUMBER=6  # Adjust this as needed

# Function to get Keycloak access token
get_keycloak_token() {
    echo "Getting Keycloak Token..."
    echo "Executing curl command to get token..."
    echo "curl -s -k -X POST \"${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token\""
    echo "-H \"Content-Type: application/x-www-form-urlencoded\""
    echo "-d \"grant_type=client_credentials&client_id=${KEYCLOAK_CLIENT_ID}&client_secret=${KEYCLOAK_CLIENT_SECRET}\""

    token_response=$(curl -s -k -X POST "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
         -d "grant_type=client_credentials&client_id=${KEYCLOAK_CLIENT_ID}&client_secret=${KEYCLOAK_CLIENT_SECRET}")

    echo "Token response: ${token_response}"  # Log the full token response

    token=$(echo "${token_response}" | jq -r '.access_token')
    echo "My token is ******* " + ${token}
    echo "****************************"
    if [ -z "${token}" ] || [ "${token}" = "null" ]; then
        echo "Failed to retrieve token. Exiting."
        exit 3  # Specific exit code for token retrieval error
    fi

    echo "Retrieved Token: ${token}"  # Display the actual token for confirmation
    echo

    # Return the token value
    return "${token}"
}

# Function to check if a user exists
check_user_exists() {
    local username=$1

    echo "Checking if user ${username} exists..."

    # Get the token from the calling scope (avoiding variable issues)
    token=$(get_keycloak_token)  # Call the function to retrieve the token

    echo "Using token: ${token}"  # Display the token being used for this request
    echo "Executing curl command to check if the user exists..."
    echo "curl -s -k -H \"Authorization: Bearer ${token}\"" + "\"${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users?username=${username}\""

    user_check=$(curl -s -k -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users?username=${username}")

    # Check for error in response and handle accordingly
    if [[ "${user_check}" == *"error"* ]]; then
        echo "Error checking user existence: ${user_check}"
        return 1
    fi

    # Check if the user exists in the response
    if [[ "${user_check}" == *"${username}"* ]]; then
        echo "User ${username} already exists."
        return 0
    fi

    echo "User ${username} does not exist."
    return 1
}

# Function to create Keycloak user
create_keycloak_user() {
    local username=$1
    local password=$2

    echo "Checking if user ${username} exists..."
    if check_user_exists "${username}"; then
        echo "Skipping creation. User ${username} exists."
        return 0
    fi

    echo "User ${username} does not exist. Preparing to create user..."
    echo "Executing curl command to create the user..."
    echo "Using endpoint: ${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users"

    # Print the complete curl command with data for comparison
    echo "***** CREATE USER POST******"
    echo "curl -s -k -X POST \"${KEYCLOAK_URL}/auth/admin/realms/${KEYCLOAK_REALM}/users\" \
        -H \"Authorization: Bearer ${token}\" \
        -H \"Content-Type: application/json\" \
        -d "{\"username\":\"${username}\",\"enabled\":true,\"credentials\":[{\"type\":\"password\",\"value\":\"${password}\",\"temporary\":false}]}""
    echo "END CREATE USER CURL*****"
    response=$(curl -s -k -X POST "${KEYCLOAK_URL}/auth/admin/realms/${KEYCLOAK_REALM}/users" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"${username}\",\"enabled\":true,\"credentials\":[{\"type\":\"password\",\"value\":\"${password}\",\"temporary\":false}]}")

    echo "Create user response: ${response}"

    if [[ "${response}" == *"error"* ]]; then
        echo "Error creating user: ${response}"
        return 2  # Specific exit code for user creation error
    fi

    echo "User ${username} created successfully."
}

# Main execution
echo "Starting user provisioning..."

# Get the token only once and store it
KEYCLOAK_TOKEN=$(get_keycloak_token)

for i in $(seq -f "%02g" ${START_NUMBER} ${END_NUMBER}); do
    username="${USER_PREFIX}$(printf "%02d" ${i})"
    echo "Processing user ${username}..."
    create_keycloak_user "${username}" "${USER_PASSWORD}"
    echo
done

echo "User provisioning complete."