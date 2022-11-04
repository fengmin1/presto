#!/usr/bin/env bash

set -eExv -o functrace

SCRIPT_DIR=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")
PRESTOCPP_RUN_DIR="${PRESTO_HOME:-"/opt/presto/"}"
USE_ENV_PARAMS=${USE_ENV_PARAMS:-0}

source "${SCRIPT_DIR}/common.sh"

trap 'exit 2' SIGSTOP SIGINT SIGTERM SIGQUIT
trap 'failure "LINENO" "BASH_LINENO" "${BASH_COMMAND}" "${?}"; [ -z "${DEBUG}" ] && exit 1 || sleep 3600' ERR

if [[ "${DEBUG}" == "0" || "${DEBUG}" == "false" || "${DEBUG}" == "False" ]]; then DEBUG=""; fi

while getopts ':-:' optchar; do
  case "$optchar" in
    -)
      case "$OPTARG" in
        discovery-uri=*) discovery_uri="${OPTARG#*=}" ;;
        http-server-port=*) http_server_port="${OPTARG#*=}" ;;
        use-env-params) USE_ENV_PARAMS=1 ;;
        *)
          presto_args+=($optchar)
          ;;
      esac
      ;;
    *)
      presto_args+=($optchar)
      ;;
  esac
done

function node_command_line_config()
{
  printf "presto.version=0.273.3\n"                    >  "${PRESTOCPP_RUN_DIR}/config.properties"
  printf "discovery.uri=${discovery_uri}\n"            >> "${PRESTOCPP_RUN_DIR}/config.properties"
  printf "http-server.http.port=${http_server_port}\n" >> "${PRESTOCPP_RUN_DIR}/config.properties"

  printf "node.environment=intel-poland\n" >  "${PRESTOCPP_RUN_DIR}/node.properties"
  printf "node.location=torun-cluster\n"  >> "${PRESTOCPP_RUN_DIR}/node.properties"
  printf "node.id=${NODE_UUID}\n"        >> "${PRESTOCPP_RUN_DIR}/node.properties"
  printf "node.ip=$(hostname -I)\n"      >> "${PRESTOCPP_RUN_DIR}/node.properties"
}

function node_configuration()
{
  cat "${PRESTOCPP_RUN_DIR}/config.properties.template" > "${PRESTOCPP_RUN_DIR}/config.properties"
  cat "${PRESTOCPP_RUN_DIR}/node.properties.template" > "${PRESTOCPP_RUN_DIR}/node.properties"

  [ -z "$NODE_UUID" ] && NODE_UUID=$(uuid) || return -2

  if [[ -z "$(grep -E '^ *node\.id=' "${PRESTOCPP_RUN_DIR}/node.properties" | cut -d'=' -f2)" ]]
  then
    printf "node.id=${NODE_UUID}\n" >> "${PRESTOCPP_RUN_DIR}/node.properties"
  fi
  printf "node.ip=$(hostname -I)\n" >> "${PRESTOCPP_RUN_DIR}/node.properties"
}

[ $USE_ENV_PARAMS == "1" ] && node_command_line_config || node_configuration

cd "${PRESTOCPP_RUN_DIR}"
"${PRESTOCPP_RUN_DIR}/presto_server" --logtostderr=1 --v=1 "${presto_args[@]}"
