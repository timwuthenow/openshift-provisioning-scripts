for i in $(seq -w 1 30)
do
  oc create namespace student$1-namespace
  # Create RoleBinding
  oc create rolebinding student$i-admin --clusterrole=admin --user=student$i -n student$i-namespace
done