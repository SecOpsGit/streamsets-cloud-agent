#!/usr/bin/env bash
# Copyright 2019 Streamsets Inc.

if [[ $# -eq 0 ]]; then
  NS="default"
elif [[ $# -eq 2 && "$1" == "--namespace" ]]; then
  NS="$2"
else
  echo "Usage: ./delagent.sh --namespace <namespace>"
  exit 1
fi

read -p "You are about to delete the StreamSets Cloud agent in the namespace $NS. This action cannot be reversed. Type Y to continue (anything else will quit): " RESPONSE
[[ $RESPONSE != "Y" ]] && exit 0

# Get the directory the script is from
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

INGRESS_NAME=$(kubectl get ingress | grep -i "agent-ingress")
INGRESS_TYPE=$(echo $INGRESS_NAME  | awk '{print $1}' | awk -F "-" '{print $1}')

# Usually you want to use this alias so namespaces are handled for you
KUBECTL_NS="kubectl -n $NS"

$KUBECTL_NS delete configmap launcher-conf
$KUBECTL_NS delete secret agenttls

$KUBECTL_NS delete configmap executor-cmd-config

$KUBECTL_NS delete -f "$SCRIPT_DIR"/yaml/streamsets-agent-service.yaml
$KUBECTL_NS delete -f "$SCRIPT_DIR"/yaml/streamsets-agent.yaml
$KUBECTL_NS delete -f "$SCRIPT_DIR"/yaml/streamsets-agent-roles.yaml

[[ $INGRESS_TYPE == 'nginx' ]] && \
 kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.24.1/deploy/provider/cloud-generic.yaml \
  && kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.24.1/deploy/mandatory.yaml \
  && kubectl delete -f "$SCRIPT_DIR"/yaml/nginx_ingress.yaml

[[ $INGRESS_TYPE == 'gke' ]] && kubectl delete -f "$SCRIPT_DIR"/yaml/gke_ingress.yaml
[[ $INGRESS_TYPE == 'aks' ]] && kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.24.1/deploy/provider/cloud-generic.yaml \
  && kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.24.1/deploy/mandatory.yaml \
  && kubectl delete -f "$SCRIPT_DIR"/yaml/aks_ingress.yaml

[[ $INGRESS_TYPE == 'minikube' ]] && kubectl delete -f "$SCRIPT_DIR"/yaml/minikube_ingress.yaml

[[ -f "$SCRIPT_DIR/yaml/pv-dir-mount.yaml" ]] && kubectl delete -f "$SCRIPT_DIR"/yaml/pv-dir-mount.yaml

[[ $NS != "default" ]] && kubectl delete namespace $NS

rm -rf "$SCRIPT_DIR"
