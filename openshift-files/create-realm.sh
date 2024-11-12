#!/bin/bash

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


# Keycloak settings
REALM="jbpm-openshift"
CLIENT_ID="task-console"
KEYCLOAK_SERVICE=keycloak
BASE_URL="apps.sandbox-m2.ll9k.p1.openshiftapps.com"
KEYCLOAK_URL="https://$KEYCLOAK_SERVICE-$namespace.$BASE_URL/auth"

# Admin credentials - replace these with your actual admin username and password
ADMIN_USERNAME="admin"
ADMIN_PASSWORD="admin"

# Function to prompt for yes/no confirmation
confirm() {
    while true; do
        read -p "$1 [y/n]: " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Prompt for workshop or solo application
if confirm "Is this for a workshop (y) or a solo application (n)?"; then
    WORKSHOP=true
    echo "Setting up for workshop..."
else
    WORKSHOP=false
    # read -p "Enter the namespace for the solo application: " SOLO_NAMESPACE
    echo "Setting up for solo application with namespace: $namespace"
fi

# Get access token
get_token() {
    TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=password" \
      -d "client_id=admin-cli" \
      -d "username=${ADMIN_USERNAME}" \
      -d "password=${ADMIN_PASSWORD}")

    TOKEN=$(echo $TOKEN_RESPONSE | jq -r '.access_token' 2>/dev/null)

    if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
      echo "Failed to obtain access token. Check your credentials and Keycloak configuration."
      echo "Response from Keycloak:"
      echo "$TOKEN_RESPONSE"
      exit 1
    fi
}

# Create realm
create_realm() {
    REALM_PAYLOAD=$(jq -n \
      --arg realm "$REALM" \
      '{realm: $realm, enabled: true}')

    RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d "${REALM_PAYLOAD}")

    if [ -z "$RESPONSE" ]; then
      echo "Realm created successfully."
    else
      echo "Failed to create realm. Response: ${RESPONSE}"
      exit 1
    fi
}

# Create client
create_client() {
    CLIENT_PAYLOAD=$(jq -n \
      --arg clientId "$CLIENT_ID" \
      '{clientId: $clientId, enabled: true, publicClient: false, redirectUris: ["*"], webOrigins: ["*"]}')

    RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d "${CLIENT_PAYLOAD}")

    if [ -z "$RESPONSE" ]; then
      echo "Client created successfully."
    else
      echo "Failed to create client. Response: ${RESPONSE}"
      exit 1
    fi
}

# Update client configuration
update_client_config() {
    # Get current client configuration
    CLIENT_CONFIG=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" | jq ".[] | select(.clientId==\"${CLIENT_ID}\")")

    if [ -z "$CLIENT_CONFIG" ]; then
      echo "Client ${CLIENT_ID} not found in realm ${REALM}."
      exit 1
    fi

    # Extract current redirectUris and webOrigins
    REDIRECT_URIS=$(echo $CLIENT_CONFIG | jq -r '.redirectUris')
    WEB_ORIGINS=$(echo $CLIENT_CONFIG | jq -r '.webOrigins')

    if [ "$WORKSHOP" = true ]; then
      # Add new URIs for student01 to student30
      for i in $(seq -f "%02g" 1 30)
      do
        NEW_REDIRECT_URI="https://task-console-student${i}-namespace.$BASE_URL/*"
        NEW_WEB_ORIGIN="https://task-console-student${i}-namespace.$BASE_URL"
        
        REDIRECT_URIS=$(echo $REDIRECT_URIS | jq ". + [\"$NEW_REDIRECT_URI\"]")
        WEB_ORIGINS=$(echo $WEB_ORIGINS | jq ". + [\"$NEW_WEB_ORIGIN\"]")
      done
    else
      # Add URIs for solo application
      NEW_REDIRECT_URI="https://task-console-${namespace}.$BASE_URL/*"
      NEW_WEB_ORIGIN="https://task-console-${namespace}.$BASE_URL"
      
      REDIRECT_URIS=$(echo $REDIRECT_URIS | jq ". + [\"$NEW_REDIRECT_URI\"]")
      WEB_ORIGINS=$(echo $WEB_ORIGINS | jq ". + [\"$NEW_WEB_ORIGIN\"]")
    fi

    # Remove duplicates
    REDIRECT_URIS=$(echo $REDIRECT_URIS | jq 'unique')
    WEB_ORIGINS=$(echo $WEB_ORIGINS | jq 'unique')

    # Update client configuration
    CLIENT_ID_INTERNAL=$(echo $CLIENT_CONFIG | jq -r '.id')
    UPDATE_PAYLOAD=$(jq -n \
      --argjson redirectUris "$REDIRECT_URIS" \
      --argjson webOrigins "$WEB_ORIGINS" \
      '{redirectUris: $redirectUris, webOrigins: $webOrigins}')

    RESPONSE=$(curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${CLIENT_ID_INTERNAL}" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d "${UPDATE_PAYLOAD}")

    if [ -z "$RESPONSE" ]; then
      echo "Client configuration updated successfully."
    else
      echo "Failed to update client configuration. Response: ${RESPONSE}"
    fi
}

# Main execution
get_token
create_realm
create_client
update_client_config

echo "Script execution completed."