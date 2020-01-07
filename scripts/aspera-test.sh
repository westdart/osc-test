#!/usr/bin/env bash
#
# Instruction: source this file first then use the functions to test.
# Setup: 't1c' and 't2c' are aliases that establish a login session on the respective cluster
# Functions:
#   do_central_send              : Instigate sending a file from Central to Deployed
#   do_deployed_send             : Instigate sending a file from Deployed to Central
#   get_central_transfer_status  : Get the status of the central file transfer
#   get_deployed_transfer_status : Get the status of the deployed file transfer
#   print_env                    : Print the environment variables used in tests
#
source "$(dirname ${BASH_SOURCE[0]})/logger.sh"

shopt -s expand_aliases
RED='\033[1;31m'
NC='\033[0m' # No Color

alias osmh='grep ${ENV_ID}.master /etc/hosts | awk '"'"'{print $NF}'"'"
alias t1c='export ENV_ID=t1 && oc login https://$(osmh):8443 -u admin -p password > /dev/null'
alias t2c='export ENV_ID=t2 && oc login https://$(osmh):8443 -u admin -p password > /dev/null'

export CENTRAL_CLUSTER=t1
export DEPLOYED_CLUSTER=t2

export CENTRAL_NS='dif-dev'
export DEPLOYED_NS='test101-dev'

export ASPERA_USER=aspera
export ASPERA_PASSWORD=GFQDprRXGwGkPNeIbdadpoHaz

t1c
export ENV_ID=${CENTRAL_CLUSTER} && oc login https://$(osmh):8443 -u admin -p password > /dev/null
export CENTRAL_HOST=$(oc get route -n ${CENTRAL_NS} | grep '\-aspera-api' | awk '{print $2}')
export CENTRAL_DEPLOYED_FILE=centralToDeployedFile.txt
export aspera_central_pod=$(oc get pods -n ${CENTRAL_NS} | grep "aspera.*Running" | awk '{print $1}')
echo "touch /desbs/stg/out/${CENTRAL_DEPLOYED_FILE}" | oc rsh -n ${CENTRAL_NS} ${aspera_central_pod}
export CENTRAL_TOKEN=$(echo -n 'MjdiCentral:/desbs/stg' | base64)
export CENTRAL_SSH_PORT=30001
export CENTRAL_FASP_PORT=30002
export CENTRAL_COMPUTE_NODE=$(oc get nodes -l "node-role.kubernetes.io/compute=true" | tail -n1 | awk '{print $1}')
export CENTRAL_MASTER_NODE=$(oc get nodes -l "node-role.kubernetes.io/master=true" | tail -n1 | awk '{print $1}')

t2c
export ENV_ID=${DEPLOYED_CLUSTER} && oc login https://$(osmh):8443 -u admin -p password > /dev/null
export DEPLOYED_HOST=$(oc get route -n ${DEPLOYED_NS} | grep '\-aspera-api' | awk '{print $2}')
export DEPLOYED_CENTRAL_FILE=deployedToCentralFile.txt
export aspera_deployed_pod=$(oc get pods -n ${DEPLOYED_NS} | grep "aspera.*Running" | awk '{print $1}')
echo "touch /mjdi/local/GFT/out/${DEPLOYED_CENTRAL_FILE}" | oc rsh -n ${DEPLOYED_NS} ${aspera_deployed_pod}
export DEPLOYED_TOKEN=$(echo -n 'MjdiDeployed:/mjdi/local/GFT' | base64)
export DEPLOYED_SSH_PORT=30001
export DEPLOYED_FASP_PORT=30002
export DEPLOYED_COMPUTE_NODE=$(oc get nodes -l "node-role.kubernetes.io/compute=true" | tail -n1 | awk '{print $1}')
export DEPLOYED_MASTER_NODE=$(oc get nodes -l "node-role.kubernetes.io/master=true" | tail -n1 | awk '{print $1}')

export ENV_ID=

function basic_tests()
{
    # Basic tests
    echo "/opt/aspera/bin/asnodeadmin -l" | oc rsh -n ${CENTRAL_NS} ${aspera_central_pod}
    echo "/opt/aspera/bin/asnodeadmin -l" | oc rsh -n ${DEPLOYED_NS} ${aspera_deployed_pod}

    # Browse
    printf "\n${RED}Browse of ${CENTRAL_HOST}${NC}\n"
    curl -ki -H "Authorization: Basic ${CENTRAL_TOKEN}" -d '{"filters":{"basenames":["*File*.txt"],"types":["file","directory"]},"path":"/out","sort":"mtime_a"}' https://${CENTRAL_HOST}/files/browse
    printf "\n${RED}Browse of ${DEPLOYED_HOST}${NC}\n"
    curl -ki -H "Authorization: Basic ${DEPLOYED_TOKEN}" -d '{"filters":{"basenames":["*File*.txt"],"types":["file","directory"]},"path":"/out","sort":"mtime_a"}' https://${DEPLOYED_HOST}/files/browse
    printf "\n"
}

function set_json()
{
    local src=$1
    local dest_machine=
    local ssh_port=
    local fasp_port=

    [[ $# -gt 1 ]] && dest_machine=$2
    [[ $# -gt 2 ]] && ssh_port=$3
    [[ $# -gt 3 ]] && fasp_port=$4

    local src_machine=
    local src_token=
    local dest_token=

    if [[ "${src}" == "CENTRAL" ]]
    then
        src_machine=${CENTRAL_HOST}
        src_token=${CENTRAL_TOKEN}
        dest_token=${DEPLOYED_TOKEN}
        file=${CENTRAL_DEPLOYED_FILE}
        [[ -z "${dest_machine}" ]] && dest_machine=${DEPLOYED_HOST}
        [[ -z "${ssh_port}" ]] && ssh_port=${DEPLOYED_SSH_PORT}
        [[ -z "${fasp_port}" ]] && fasp_port=${DEPLOYED_FASP_PORT}
    elif [[ "${src}" == "DEPLOYED" ]]
    then
        src_machine=${DEPLOYED_HOST}
        src_token=${DEPLOYED_TOKEN}
        dest_token=${CENTRAL_TOKEN}
        file=${DEPLOYED_CENTRAL_FILE}
        [[ -z "${dest_machine}" ]] && dest_machine=${CENTRAL_HOST}
        [[ -z "${ssh_port}" ]] && ssh_port=${CENTRAL_SSH_PORT}
        [[ -z "${fasp_port}" ]] && fasp_port=${CENTRAL_FASP_PORT}
    else
        src_machine=${1}
        src_token=${2}
        dest_machine=${3}
        dest_token=${4}
        file=${5}
        ssh_port=${6}
        fasp_port=${7}
    fi
    export JSON=$(echo "'"$(printf '{"direction":"send","remote_host":"%s","remote_user":"%s","remote_password":"%s","token":"Basic %s","fasp_port":%s,"ssh_port":%s,"paths":[{"source":"/out/%s","destination":"/in/%s"}]}' \
 ${dest_machine} ${ASPERA_USER} ${ASPERA_PASSWORD} ${dest_token} ${fasp_port} ${ssh_port} ${file} ${file})"'")

}

function set_json_central_to_deployed_using_docker_net()
{
    set_json ${CENTRAL_COMPUTE_NODE} \
             ${CENTRAL_TOKEN} \
             $(oc get pods -n test101-dev -o wide | grep 'aspera.*Running' | awk '{print $6}') \
             ${DEPLOYED_TOKEN} \
             ${CENTRAL_DEPLOYED_FILE} \
             33001 \
             33001
}

function set_json_central_to_deployed()
{
    set_json ${CENTRAL_COMPUTE_NODE} \
             ${CENTRAL_TOKEN} \
             ${DEPLOYED_COMPUTE_NODE} \
             ${DEPLOYED_TOKEN} \
             ${CENTRAL_DEPLOYED_FILE} \
             ${DEPLOYED_SSH_PORT} \
             ${DEPLOYED_FASP_PORT}
}

function set_json_deployed_to_central()
{
    set_json ${DEPLOYED_COMPUTE_NODE} \
             ${DEPLOYED_TOKEN} \
             ${CENTRAL_COMPUTE_NODE} \
             ${CENTRAL_TOKEN} \
             ${DEPLOYED_CENTRAL_FILE} \
             ${CENTRAL_SSH_PORT} \
             ${CENTRAL_FASP_PORT}
}

function test_curl()
{
    cmd=$@
    ret=$(curl -ki -w "%{http_code}" -o /dev/null $cmd 2>/dev/null)
    [[ "$ret" == "200" ]] || { log_info "failed: curl -ki $cmd"; return 1; }
}


function check_access_keys()
{
    if test_curl "-u asperaNodeUser:Password123 -X GET https://${CENTRAL_HOST}/access_keys"
    then
        log_info "Successfully checked curl of access keys at https://${CENTRAL_HOST}/access_keys"
    else
        log_info "Failed to check curl of access keys at https://${CENTRAL_HOST}/access_keys"
    fi
}

function do_central_send()
{
    [[ -z "$JSON" ]] && set_json_central_to_deployed
    log_info "Posting the following JSON:\n ${JSON}"

    id=$(eval $(echo curl -k -H \"Authorization: Basic ${CENTRAL_TOKEN}\" -X POST https://${CENTRAL_HOST}/ops/transfers -d ${JSON}) | jq '.id' | awk -F '"' '{print $2}')
    export TX_ID=$id
    get_central_transfer_status
    echo "use 'get_central_transfer_status' to get update on status"
    echo "TX_ID=$id"
}

function do_deployed_send()
{
    [[ -z "$JSON" ]] && set_json_deployed_to_central
    log_info "Posting the following JSON:\n ${JSON}"

    id=$(eval $(echo curl -k -H \"Authorization: Basic ${DEPLOYED_TOKEN}\" -X POST https://${DEPLOYED_HOST}/ops/transfers -d ${JSON}) | jq '.id' | awk -F '"' '{print $2}')
    export TX_ID=$id
    get_deployed_transfer_status
    echo "use 'get_deployed_transfer_status' to get update on status"
    echo "TX_ID=$id"
}

function get_central_transfer_status()
{
    local id=$1
    [[ -z "$id" ]] && id=$TX_ID
    curl -ki -H "Authorization: Basic ${CENTRAL_TOKEN}" -X GET https://${CENTRAL_HOST}/ops/transfers/${id}
}

function get_deployed_transfer_status()
{
    local id=$1
    [[ -z "$id" ]] && id=$TX_ID
    curl -ki -H "Authorization: Basic ${DEPLOYED_TOKEN}" -X GET https://${DEPLOYED_HOST}/ops/transfers/${id}
}

function print_env()
{
    log_always "CENTRAL ENV VARS:"
    log_always "CENTRAL_HOST:          ${CENTRAL_HOST}"
    log_always "CENTRAL_DEPLOYED_FILE: ${CENTRAL_DEPLOYED_FILE}"
    log_always "aspera_central_pod:    ${aspera_central_pod}"
    log_always "CENTRAL_TOKEN:         ${CENTRAL_TOKEN}"
    log_always "CENTRAL_FASP_PORT:     ${CENTRAL_FASP_PORT}"
    log_always "CENTRAL_COMPUTE_NODE:  ${CENTRAL_COMPUTE_NODE}"
    log_always "CENTRAL_MASTER_NODE:   ${CENTRAL_MASTER_NODE}"
    log_always "DEPLOYED ENV VARS:"
    log_always "DEPLOYED_HOST:         ${DEPLOYED_HOST}"
    log_always "DEPLOYED_CENTRAL_FILE: ${DEPLOYED_CENTRAL_FILE}"
    log_always "aspera_deployed_pod:   ${aspera_deployed_pod}"
    log_always "DEPLOYED_TOKEN:        ${DEPLOYED_TOKEN}"
    log_always "DEPLOYED_SSH_PORT:     ${DEPLOYED_SSH_PORT}"
    log_always "DEPLOYED_FASP_PORT:    ${DEPLOYED_FASP_PORT}"
    log_always "DEPLOYED_COMPUTE_NODE: ${DEPLOYED_COMPUTE_NODE}"
    log_always "DEPLOYED_MASTER_NODE:  ${DEPLOYED_MASTER_NODE}"
}
