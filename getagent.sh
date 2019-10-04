#!/usr/bin/env bash
# Copyright 2019 Streamsets Inc.

cd ~
if [[ ! -d ".streamsets" ]]; then
  mkdir .streamsets
fi
cd .streamsets

if [[ ! -d "cloudenv" ]]; then
  mkdir cloudenv
fi
cd cloudenv

mkdir tmp && cd tmp

readonly SCRIPT_URL=https://raw.githubusercontent.com/streamsets/streamsets-cloud-agent/master

# Download script files
curl -O -s "$SCRIPT_URL"/agent_commands.sh
curl -O -s "$SCRIPT_URL"/delagent.sh
curl -O -s "$SCRIPT_URL"/previewer-crd.yaml
curl -O -s "$SCRIPT_URL"/template-fetcher.conf
curl -O -s "$SCRIPT_URL"/template-launcher.conf
curl -O -s "$SCRIPT_URL"/run_executor.sh
curl -O -s "$SCRIPT_URL"/update-conf.sh

mkdir yaml && cd yaml

curl -O -s "$SCRIPT_URL"/yaml/aks_ingress.yaml
curl -O -s "$SCRIPT_URL"/yaml/gke_ingress.yaml
curl -O -s "$SCRIPT_URL"/yaml/metric-server.yaml
curl -O -s "$SCRIPT_URL"/yaml/minikube_ingress.yaml
curl -O -s "$SCRIPT_URL"/yaml/nginx_ingress.yaml
curl -O -s "$SCRIPT_URL"/yaml/pv-extrta-lib.yaml
curl -O -s "$SCRIPT_URL"/yaml/pv-gpd.yaml
curl -O -s "$SCRIPT_URL"/yaml/pv-hostpath.yaml
curl -O -s "$SCRIPT_URL"/yaml/pvc-test.yaml
curl -O -s "$SCRIPT_URL"/yaml/streamsets-agent-roles.yaml
curl -O -s "$SCRIPT_URL"/yaml/streamsets-agent-service.yaml
curl -O -s "$SCRIPT_URL"/yaml/template-pv-dir-mount.yaml
curl -O -s "$SCRIPT_URL"/yaml/template-streamsets-agent.yaml

cd .. && mkdir util && cd util

curl -O -s "$SCRIPT_URL"/util/validators.sh
curl -O -s "$SCRIPT_URL"/util/usage.sh

cd ..

source util/validators.sh # utilities for validating files, commands etc as pre-reqs

source util/usage.sh # Usage in file to improve readability

function cleanup() {
  rm -rf $HOME/.streamsets/cloudenv/tmp
}

# Check that the arguments either begin with -h, all needed args are set as env variables, or all args are present
if [[ $# -gt 0 && "$1" == "-h" ]]; then
  usage
  cleanup
  exit 0
elif [[ $# -ge 10 ]]; then
  while [[ -n "$1" ]]; do
    if [[ -z "$2" ]]; then
      usage
      cleanup
      exit 1
    fi
    case "$1" in
      --install-type)
        INSTALL_TYPE="$2"
        ;;
      --agent-id)
        AGENT_ID="$2"
        ;;
      --credentials)
        AGENT_CREDENTIALS="$2"
        ;;
      --environment-id)
        ENV_ID="$2"
        ;;
      --streamsets-cloud-url)
        STREAMSETS_CLOUD_URL="$2"
        ;;
      --external-url)
        INGRESS_URL="$2"
        ;;
      --hostname)
        PUBLICIP="$2"
        ;;
      --agent-crt)
        AGENT_CRT="$2"
        ;;
      --agent-key)
        AGENT_KEY="$2"
        ;;
      --directory)
        PATH_MOUNT="$2"
        ;;
      --namespace)
        NS="$2"
        ;;
      --port)
        PORT="$2"
        ;;
    esac
    shift
    shift
  done
fi

if [[ -z "$AGENT_ID" || -z "$AGENT_CREDENTIALS" || -z "$ENV_ID" || -z "$STREAMSETS_CLOUD_URL" || -z "$INSTALL_TYPE" ]]; then
  incorrectUsage
  usage
  cleanup
  exit 1
fi
if [[ $INSTALL_TYPE == "LINUX_VM" && -z "$PUBLICIP" ]]; then
  incorrectUsage
  usage
  cleanup
  exit 1
fi
if [[ ( -n "$AGENT_KEY" && -z "$AGENT_CRT") || ( -z "$AGENT_KEY" && -n "$AGENT_CRT") ]]; then
  echo "Missing agent key or certificate"
  cleanup
  exit 1
fi
if [[ -n "$PATH_MOUNT" && $INSTALL_TYPE != "LINUX_VM" ]]; then
  echo "Directory to mount specified on an install type which does not support mounted directories"
  cleanup
  exit 1
fi
if [[ -n "$PORT" && $INSTALL_TYPE != "LINUX_VM" ]]; then
  echo "Warning: Agent port can only be set on Linux VM installations and will be ignored"
fi
if [[ $INSTALL_TYPE == "LINUX_VM" && -n "$PORT" && ( "$PORT" -lt 30000 || "$PORT" -gt 32767 ) ]]; then
  echo "Error: The specified port is outside the usable range of 30000-32767"
  cleanup
  exit 1
fi

# Set port to 30300 if the user did not specify another
[[ -z "$PORT" ]] && PORT=30300

if [[ -d $HOME/.streamsets/cloudenv/$ENV_ID ]]; then
  echo "Error: installation already exists for environment with this ID"
  cleanup
  exit 1
fi
mv $HOME/.streamsets/cloudenv/tmp $HOME/.streamsets/cloudenv/$ENV_ID
chmod u+x delagent.sh

function printN() {
  for i in `seq $1`
  do
    printf '*'
  done
  printf '\n'
}

# Get the directory the script is from
SCRIPT_DIR="$(dirname "$(readlink "$0")")"

validate_file "${SCRIPT_DIR}/yaml/metric-server.yaml"
validate_file "${SCRIPT_DIR}/yaml/template-streamsets-agent.yaml"
validate_file "${SCRIPT_DIR}/update-conf.sh"
validate_file "${SCRIPT_DIR}/template-launcher.conf"
validate_file "${SCRIPT_DIR}/template-fetcher.conf"
validate_file "${SCRIPT_DIR}/yaml/streamsets-agent-roles.yaml"

# Need to generate UUIDs, uuidgen is available on OSX and most Linux else cat
UUID_COMMAND="uuidgen"
if [[ -z $(which uuidgen) ]]; then
  UUID_COMMAND="cat /proc/sys/kernel/random/uuid"
fi

NS=${NS:-default}
# Usually you want to use this alias so namespaces are handled for you
KUBECTL_NS="kubectl -n $NS"

# Check for resources left from previous runs of this script
if [[ -n $($KUBECTL_NS get deployments --field-selector=metadata.name=launcher 2> /dev/null) || \
      -n $($KUBECTL_NS get ingress 2> /dev/null | grep agent-ingress) || \
      -n $($KUBECTL_NS get configmaps --field-selector=metadata.name=launcher-conf 2> /dev/null) || \
      -n $($KUBECTL_NS get svc --field-selector=metadata.name=streamsets-agent 2> /dev/null) ]]; then
  echo "Agent resources found in this namespace."
  echo "Either delete these resources by running delagent.sh or specify a different namespace (under Advanced options in the Install Agent screen) and retry to continue."
  exit 1
fi

# Install Kubernetes and its dependencies
if [[ $INSTALL_TYPE == "LINUX_VM" ]]; then
  # Install kubernetes
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 664" sh -s -

  # Wait for Kubernetes to start up
  until [[ $(kubectl get namespaces | grep "default") ]] && kubectl cluster-info ; do
    sleep 1
  done
fi

[[ $INSTALL_TYPE == "LINUX_VM" ]] || [[ $INSTALL_TYPE == "DOCKER" ]] || [[ $INSTALL_TYPE == "AKS" ]] && kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.24.1/deploy/mandatory.yaml

[[ $INSTALL_TYPE == "LINUX_VM" ]] || [[ $INSTALL_TYPE == "DOCKER" ]] || [[ $INSTALL_TYPE == "AKS" ]] && kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.24.1/deploy/provider/cloud-generic.yaml

#[[ $INSTALL_TYPE == "DOCKER" ]] &&  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.24.1/deploy/provider/baremetal/service-nodeport.yaml

[[ $NS != "default" ]] && kubectl create namespace $NS

$KUBECTL_NS create -f yaml/streamsets-agent-service.yaml

# Create config
source update-conf.sh


[[ ! -z "$PATH_MOUNT" ]] && $KUBECTL_NS create -f yaml/pv-dir-mount.yaml

# Deploy the configuration for the operator
$KUBECTL_NS create configmap launcher-conf --from-file=launcher.conf

# Deploy the configuration for executor start
$KUBECTL_NS create configmap executor-cmd-config --from-file run_executor.sh

# Install Agent Roles
$KUBECTL_NS apply -f yaml/streamsets-agent-roles.yaml

# Install Agent
$KUBECTL_NS apply -f yaml/streamsets-agent.yaml

# Wait for Agent to start up
WAIT_MESSAGE="Starting Agent. This may take a few minutes...."
if [[ $INSTALL_TYPE == "GKE" ]]; then
  WAIT_MESSAGE="Starting Agent. This may take up to 20 minutes...."
fi

i=1
sp="/-\|"
echo -n "$WAIT_MESSAGE"
until [[ $($KUBECTL_NS get pods -l app=launcher --field-selector=status.phase=Running 2> /dev/null) ]] && curl -Lf -k "$INGRESS_URL" -o /dev/null 2> /dev/null; do
  printf "\b${sp:i++%${#sp}:1}"
  sleep 1
done

AGENT_RUNNING_MESSAGE="Agent is running at: $INGRESS_URL"
[[  $SHOULD_ACCEPT_SELF_SIGNED == 1 ]] && CERTIFICATE_MESSAGE="Go to $INGRESS_URL in the browser and accept the self-signed certificate."
[[  $SHOULD_ACCEPT_SELF_SIGNED == 1 ]] && COLS=${#CERTIFICATE_MESSAGE} || COLS=${#AGENT_RUNNING_MESSAGE}
((COLS+=10))

echo ""
printN $COLS
echo ""
echo "     $AGENT_RUNNING_MESSAGE"
echo "     $CERTIFICATE_MESSAGE"
echo ""
printN $COLS
