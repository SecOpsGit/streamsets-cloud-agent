#!/usr/bin/env bash
# Copyright 2019 Streamsets Inc.
set +e

source util/validators.sh

function initIngressUrl() {
  if [[ -z "$INGRESS_URL" ]]; then
   while [[ -z $PUBLICIP ]]; do
    echo "Waiting for Agent Ingress to start. This may take several minutes..."
    [[ $INSTALL_TYPE == "AKS" ]] && PUBLICIP=$(kubectl get ingress aks-agent-ingress -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
    [[ $INSTALL_TYPE == "GKE" ]] && PUBLICIP=$(kubectl get ingress gke-agent-ingress -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
    [[ $INSTALL_TYPE == "LINUX_VM" ]] && PUBLICIP=$(kubectl describe svc traefik --namespace kube-system | grep Ingress | awk '{print $3}')
    sleep 10
   done
   [[ $INSTALL_TYPE == "LINUX_VM" ]] && INGRESS_NODE_PORT=$(kubectl -n ingress-nginx get svc ingress-nginx -o=jsonpath='{.spec.ports[1].nodePort}')
  fi
  [[ -z "$INGRESS_URL" ]] && [[ $INSTALL_TYPE == "DOCKER" ]] || [[ $INSTALL_TYPE == "MINIKUBE" ]] && INGRESS_URL="https://$PUBLICIP/agent"
  [[ -z "$INGRESS_URL" ]] && [[ $INSTALL_TYPE == "GKE" ]] && INGRESS_URL="https://$PUBLICIP"
  [[ -z "$INGRESS_URL" ]] && [[ $INSTALL_TYPE == "AKS" ]] && INGRESS_URL="https://$PUBLICIP"
  [[ -z "$INGRESS_URL" ]] && [[ $INSTALL_TYPE == "LINUX_VM" ]] && INGRESS_URL="https://$PUBLICIP:$INGRESS_NODE_PORT/agent"
}

[[ $INSTALL_TYPE == "MINIKUBE" ]] && PUBLICIP=$(minikube ip)
[[ $INSTALL_TYPE == "DOCKER" ]] && PUBLICIP="127.0.0.1"

SHOULD_ACCEPT_SELF_SIGNED=0

if [[ -z "$AGENT_CRT" ]] && [[ -z "$AGENT_KEY" ]]; then
 SHOULD_ACCEPT_SELF_SIGNED=1
fi


if [[ -z "$AGENT_CRT" ]] && [[ -z "$AGENT_KEY" ]]; then
 AGENT_CRT=${AGENT_CRT:=agent.crt}
 AGENT_KEY=${AGENT_KEY:=agent.key}

 openssl req -newkey rsa:2048 \
   -nodes \
   -keyout $AGENT_KEY \
   -x509 \
   -days 365 \
   -out $AGENT_CRT \
   -subj "/C=US/ST=California/L=San Francisco/O=Streamsets/CN=localhost"

fi

kubectl create secret tls agenttls --key $AGENT_KEY --cert $AGENT_CRT -n $NS

[[ $INSTALL_TYPE == "LINUX_VM" ]] || [[ $INSTALL_TYPE == "DOCKER" ]] && kubectl apply -f yaml/metric-server.yaml && kubectl apply -f yaml/nginx_ingress.yaml -n $NS

[[ $INSTALL_TYPE == "MINIKUBE" ]] &&  kubectl apply -f yaml/metric-server.yaml && kubectl apply -f yaml/minikube_ingress.yaml -n $NS

[[ $INSTALL_TYPE == "GKE" ]] && kubectl apply -f yaml/gke_ingress.yaml -n $NS
[[ $INSTALL_TYPE == "AKS" ]] && kubectl apply -f yaml/aks_ingress.yaml -n $NS

initIngressUrl

if [[ $OSTYPE == "darwin"* ]]; then
  # OS X requires specifying backup file extension in sed command
  BACKUP_EXT="-i ''"
elif [[ $OSTYPE == "cygwin" ]]; then
  echo "Error: Cannot be run on Windows or Cygwin"
  exit 1
else
  BACKUP_EXT="-i''"
fi


###
###   LAUNCHER.CONF
###

validate_file "${SCRIPT_DIR}/template-launcher.conf"
cp ${SCRIPT_DIR}/template-launcher.conf ${SCRIPT_DIR}/launcher.conf

sed $BACKUP_EXT "s|Launcher Configuration|Launcher Configuration - Generated from template-launcher.conf|" launcher.conf
sed $BACKUP_EXT "s|base-url =.*|base-url =\"${STREAMSETS_CLOUD_URL}\"|" launcher.conf
sed $BACKUP_EXT "s|base-http-url =.*|base-http-url =\"${INGRESS_URL}\"|" launcher.conf
sed $BACKUP_EXT "s|fetcher-address =.*|fetcher-address =\"fetcher.${NS}.svc.cluster.local:9090\"|" launcher.conf
sed $BACKUP_EXT "s|agent-credentials =.*|agent-credentials =\"${AGENT_CREDENTIALS}\"|" launcher.conf
sed $BACKUP_EXT "s|agent-id =.*|agent-id =\"${AGENT_ID}\"|" launcher.conf
sed $BACKUP_EXT "s|environment-id =.*|environment-id =\"${ENV_ID}\"|" launcher.conf
[[ ! -z "$PATH_MOUNT" ]] && sed $BACKUP_EXT "s|default-pvc-to-mount =.*|default-pvc-to-mount =\"dirmount\"|" launcher.conf
[[ ! -z "$PATH_MOUNT" ]] && sed $BACKUP_EXT "s|default-pvc-path-to-mount =.*|default-pvc-path-to-mount =\"$PATH_MOUNT\"|" launcher.conf

####
####   FETCHER.CONF
####
#validate_file "${SCRIPT_DIR}/template-fetcher.conf"
#cp ${SCRIPT_DIR}/template-fetcher.conf ${SCRIPT_DIR}/fetcher.conf
#
#sed $BACKUP_EXT "s|Fetcher Configuration|Launcher Configuration - Generated from template-fetcher.conf|" fetcher.conf
#
#[[ ! -z "${FETCHER_GRPC_PORT}" ]] && sed $BACKUP_EXT "s|port =.*|port =\"${FETCHER_GRPC_PORT}\"|" fetcher.conf
#
#[[ ! -z "${FETCHER_WRITE_PVC}" ]] && sed $BACKUP_EXT "s|writepvc =.*|writepvc =\"${FETCHER_WRITE_PVC}\"|" fetcher.conf
#
#[[ ! -z "$FETCHER_READ_PVC" ]] && sed $BACKUP_EXT "s|readpvc =.*|readpvc =\"${FETCHER_READ_PVC}\"|" fetcher.conf

###
###   STREAMSETS-AGENT.YAML
###

validate_file "${SCRIPT_DIR}/yaml/template-streamsets-agent.yaml"
cp ${SCRIPT_DIR}/yaml/template-streamsets-agent.yaml ${SCRIPT_DIR}/yaml/streamsets-agent.yaml

sed $BACKUP_EXT "s|STREAMSETS-AGENT YAML|STREAMSETS-AGENT YAML - Generated from template-streamsets-agent.yaml|" yaml/streamsets-agent.yaml

sed $BACKUP_EXT "s|SEDTARGET1|${NS}|" yaml/streamsets-agent.yaml

[[ ! -z "$PATH_MOUNT" ]] && cp ${SCRIPT_DIR}/yaml/template-pv-dir-mount.yaml ${SCRIPT_DIR}/yaml/pv-dir-mount.yaml &&\
 sed $BACKUP_EXT "s|SEDTARGET1|${NS}|" yaml/pv-dir-mount.yaml && sed $BACKUP_EXT "s|PATH_MOUNT|${PATH_MOUNT}|" yaml/pv-dir-mount.yaml

