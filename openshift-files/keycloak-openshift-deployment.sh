# 1. Create a new project for Keycloak
oc new-project keycloak

# 2. Deploy PostgreSQL 16 for Keycloak
# oc new-app --name=postgresql \
#     --env POSTGRESQL_USER=keycloak \
#     --env POSTGRESQL_PASSWORD=keycloak \
#     --env POSTGRESQL_DATABASE=keycloak \
#     --image="postgres:16.1-alpine3.19" 

echo "Running admin command"
oc adm policy add-scc-to-user anyuid -z default -n keycloak

oc create -f postgres-pvc.yaml
oc create -f postgres-dep.yaml
oc create -f postgres-svc.yaml
sed -i 's/^\s*-/-/' postgres-route.yaml
oc create -f postgres-route.yaml

echo "Completed Postgres"

# 3. Wait for PostgreSQL to be ready
oc rollout status deployment/postgresql

# 4. Deploy Keycloak
echo "Deploying Keycloak"

oc create -f keycloak-pvc.yaml
oc create -f keycloak-dep.yaml
oc create -f keycloak-svc.yaml
oc create -f keycloak-route.yaml
# oc new-app --name=keycloak \
#     --env DB_VENDOR=postgres \
#     --env DB_ADDR=postgresql \
#     --env DB_DATABASE=keycloak \
#     --env DB_USER=keycloak \
#     --env DB_PASSWORD=keycloak \
#     --env KEYCLOAK_USER=admin \
#     --env KEYCLOAK_PASSWORD=admin \
#     --env PROXY_ADDRESS_FORWARDING=true \
#     quay.io/keycloak/keycloak:20.0.3

# 5. Expose Keycloak service

#oc create route edge keycloak --service=keycloak --port=8080

# 6. Wait for Keycloak to be ready
oc rollout status deployment/keycloak

# 7. Get the Keycloak URL

KEYCLOAK_URL=$(oc get route keycloak -o jsonpath='{.spec.host}')

# 8. Create users and link them to namespaces

for i in $(seq -w 1 30)
do
  oc create namespace student$1-namespace
  # Create RoleBinding
  oc create rolebinding student$i-admin --clusterrole=admin --user=student$i -n student$i-namespace
done

# 9. Configure OpenShift for Keycloak OIDC (this step requires manual intervention in Keycloak UI)

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

# 10. Configure OpenShift for Keycloak OIDC

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

# 11. Restart the OpenShift OAuth server to apply changes
oc delete pod -n openshift-authentication -l app=oauth-openshift
