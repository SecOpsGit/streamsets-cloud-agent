#!/usr/bin/env bash
# Copyright 2019 Streamsets Inc.

function usage() {
  echo "Usage: ./getagent.sh --install-type [INSTALL_TYPE] --agent-id [AGENT_ID] --credentials [CREDENTIALS] --environment-id [ENVIRONMENT_ID] --streamsets-cloud-url [STREAMSETS_CLOUD_URL] [OPTION]..."
}

function incorrectUsage() {
  echo "Arguments not found. Please ensure that all needed arguments are set as environment variables or all arguments are present.
  Required Arguments:
  flag                    Environment Variable      Description
  --install-type          INSTALL_TYPE              Installation type
  --agent-id              AGENT_ID                  Agent ID
  --credentials           CREDENTIALS               Agent credentials
  --environment-id        ENVIRONMENT_ID            Environment ID
  --streamsets-cloud-url  STREAMSETS_CLOUD_URL      Organization subdomain

  Optional Arguments:
  flag                    Environment Variable      Description
  --ingress-url           INGRESS_URL               The base URL to access StreamSets Agent. Default is used if none is set
  --hostname              PUBLICIP                  Hostname or IP address of Linux VM (required for LINUX_VM install type)
  --agent-crt             AGENT_CRT                 Path to agent certificate (required for non-self-signed)
  --agent-key             AGENT_KEY                 Path to agent key (required for non-self-signed)
  --directory             PATH_MOUNT                Path to directory to mount (only valid for Linux VM install type)
  "
}