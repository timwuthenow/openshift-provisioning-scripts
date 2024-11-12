namespaces=("keycloak" "student01-namespace"  "student02-namespace"  "student03-namespace"  "student04-namespace"  "student05-namespace"  "student06-namespace"  "student07-namespace"  "student08-namespace"  "student09-namespace"  "student10-namespace"  "student11-namespace"  "student12-namespace"  "student13-namespace"  "student14-namespace"  "student15-namespace"  "student16-namespace"  "student17-namespace"  "student18-namespace"  "student19-namespace"  "student20-namespace"  "student21-namespace"  "student22-namespace"  "student23-namespace"  "student24-namespace"  "student25-namespace"  "student26-namespace"  "student27-namespace"  "student28-namespace"  "student29-namespace"  "student30-namespace" )

# Loop over each namespace and create the secret
for namespace in "${namespaces[@]}"
do
  oc create -f 16260001-timwuthenowibm-pull-secret.yaml -n $namespace
done