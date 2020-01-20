#!/usr/bin/env bash
#
# Instruction: source this file first then use the functions to test. Main function is 'run_tests'
# Preparation:
#   The following are likely to need to change:
#   CENTRAL_CONSOLE_URL       : Central Cluster Console URL
#   DEPLOYED_CONSOLE_URL      : Deployed Cluster Console URL
#   CENTRAL_CONSOLE_USER      : The user that can login to the Central Console and execute 'oc' commands
#   CENTRAL_CONSOLE_PASSWORD  : The password for the Central console user (if not supplied this will be prompted for)
#   DEPLOYED_CONSOLE_USER     : The user that can login to the Deployed Console and execute 'oc' commands
#   DEPLOYED_CONSOLE_PASSWORD : The password for the Deployed console user (if not supplied this will be prompted for)
#
#   CENTRAL_NS        : Central Aspera Namespace (or Openshift Project)
#   DEPLOYED_NS       : Deployed Aspera Namespace (or Openshift Project)
#   LOCAL_DEPLOYED_NS : Deployed Aspera Namespace (or Openshift Project) on Central Cluster
#
#   ASPERA_USER     : Aspera user to access the API
#   ASPERA_PASSWORD : Password for the Aspera User (likely held in an Ansible Vault
#
# Data:
# TESTS : Bash array conforming to rows of:
#         <test-name> <instigator> <responder> <direction>
#         Where:
#           test-name: Name of test - single string
#           instigator: Name of the system instigating the transfer (CENTRAL, DEPLOYED or LOCAL_DEPLOYED)
#           responder: Name of the system responding to the transfer (CENTRAL, DEPLOYED or LOCAL_DEPLOYED)
#           direction: Direction of the transfer (send or receive)
#
# Functions:
#   central_login()                : Login to the Central Cluster console
#   deployed_login()               : Login to the Deployed Cluster console
#   os_logout()                    : Logout of whichever console that is logged in
#   setup_central_env()
#   setup_deployed_env()
#   prepare_file()                 : Create a file on the src to send (i.e. into the 'out' dir)
#   prepare_test()                 : Prepare the test, e.g. clear out an 'in' folder on the destination
#   pull_content()                 : Obtain file content of a transferred file
#   get_json()                     : Create a json payload
#   send()                         : Send a file from src to dest
#   get_transfer_status()          : Get the transfer status of a transaction
#   wait_status()                  : Wait for affirmative transfer status of a transaction
#   execute_test()                 : Execute a test
#   do_test()                      : Wrapper for test execution and verification
#   run_tests()                    : Loop over all tests and execute
#

source "$(dirname ${BASH_SOURCE[0]})/wrapper.sh"

TESTS=(
#   NAME                INSTIGATOR     RESPONDER      DIRECTION
    "central_send       CENTRAL        DEPLOYED       send"
    "deployed_send      DEPLOYED       CENTRAL        send"
    "central_send_local CENTRAL        LOCAL_DEPLOYED send"
    "local_send         LOCAL_DEPLOYED CENTRAL        send"
)

shopt -s expand_aliases
RED='\033[1;31m'
NC='\033[0m' # No Color

JQ="$(cd $(dirname ${BASH_SOURCE[0]})/../bin; pwd)/jq"

export CENTRAL_HOST=$(grep t1.master /etc/hosts | awk '{print $NF}')
export DEPLOYED_HOST=$(grep t2.master /etc/hosts | awk '{print $NF}')
export CENTRAL_CONSOLE_URL="https://${CENTRAL_HOST}:8443"
export DEPLOYED_CONSOLE_URL="https://${DEPLOYED_HOST}:8443"
export CENTRAL_CONSOLE_USER=admin
export CENTRAL_CONSOLE_PASSWORD=password
export DEPLOYED_CONSOLE_USER=admin
export DEPLOYED_CONSOLE_PASSWORD=password

export CENTRAL_NS='dif-dev'
export DEPLOYED_NS='test101-dev'
export LOCAL_DEPLOYED_NS='test102-dev'

export CENTRAL_ROOT_PATH='/desbs/stg'
export DEPLOYED_ROOT_PATH='/mjdi/local/GFT'

export CENTRAL_TOKEN=$(echo -n "MjdiCentral:${CENTRAL_ROOT_PATH}" | base64)
export DEPLOYED_TOKEN=$(echo -n "MjdiDeployed:${DEPLOYED_ROOT_PATH}" | base64)

export ASPERA_USER=aspera
# New value for when Docker builds are done : export ASPERA_PASSWORD=swEeLayVNNQHeImUDTHBRvoEt
export ASPERA_PASSWORD=swEeLayVNNQHeImUDTHBRvoEt

export SSH_NODE_PORT=30001
export FASP_NODE_PORT=30002
export SSH_INTERNAL_PORT=30001
export FASP_INTERNAL_PORT=30002

function current_host()
{
    oc whoami --show-server | awk -F "/" '{print $NF}' | awk -F ":" '{print $1}'
}

function central_login()
{
    [[ "$(current_host)" == "$CENTRAL_HOST" ]] && return 0;
    os_logout
    log_debug "Logging into Central: ${CENTRAL_CONSOLE_URL} as ${CENTRAL_CONSOLE_USER} (may require a password ...)"
    oc login ${CENTRAL_CONSOLE_URL} -u ${CENTRAL_CONSOLE_USER} -p ${CENTRAL_CONSOLE_PASSWORD} &> /dev/null
}

function deployed_login()
{
    [[ "$(current_host)" == "$DEPLOYED_HOST" ]] && return 0;
    os_logout
    log_debug "Logging into Deployed: ${DEPLOYED_CONSOLE_URL} as ${DEPLOYED_CONSOLE_USER} (${DEPLOYED_CONSOLE_PASSWORD}) (may require a password ...)"
    oc login ${DEPLOYED_CONSOLE_URL} -u ${DEPLOYED_CONSOLE_USER} -p ${DEPLOYED_CONSOLE_PASSWORD} &> /dev/null
}

function os_logout()
{
    oc logout &> /dev/null
}

function basic_test()
{
    local target=$1
    # Basic tests
    oc_login ${target}
    echo "/opt/aspera/bin/asnodeadmin -l" | oc rsh -n $(getNamespace ${target}) $(getPod ${target})

    # Browse
    printf "\n${RED}Browse of $(getHost ${target})${NC}\n"
    curl -ki -H "Authorization: Basic $(getToken ${target})" -d '{"filters":{"basenames":["*File*.txt"],"types":["file","directory"]},"path":"/out","sort":"mtime_a"}' https://$(getHost ${target})/files/browse
    curl -ki -H "Authorization: Basic $(getToken ${target})" -d '{"filters":{"basenames":["*File*.txt"],"types":["file","directory"]},"path":"/in","sort":"mtime_a"}' https://$(getHost ${target})/files/browse
    printf "\n"
}

function basic_tests()
{
    targets=$@
    # Basic tests
    [[ $# == 0 ]] && targets="CENTRAL DEPLOYED LOCAL_DEPLOYED"

    for target in ${targets}
    do
        basic_test ${target}
    done
}

function test_curl()
{
    cmd=$@
    ret=$(curl -ki -w "%{http_code}" -o /dev/null $cmd 2>/dev/null)
    [[ "$ret" == "200" ]] || { log_info "failed: curl -ki $cmd"; return 1; }
}

function check_access_key()
{
    local target=$1
    if test_curl "-u asperaNodeUser:Password123 -X GET https://$(getHost ${target})/access_keys"
    then
        log_info "Successfully checked curl of access keys at https://$(getHost ${target})/access_keys"
    else
        log_info "Failed to check curl of access keys at https://$(getHost ${target})/access_keys"
    fi
}

function check_access_keys()
{
    targets=$@
    [[ $# == 0 ]] && targets="CENTRAL DEPLOYED LOCAL_DEPLOYED"

    for target in ${targets}
    do
        check_access_key ${target}
    done
}

function getTestFileName()
{
    local name=$1
    echo "/out/${name}.file"
}

function getResultFileName()
{
    local name=$1
    echo "/in/${name}.file"
}

function prepare_file()
{
    LOG_ENTRY
    local name=$1
    local instigator=$2
    local responder=$3
    local direction=$4
    local content=$5
    [[ -z $content ]] && content=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')
    local root_path=
    local namespace=
    local pod=

    local src=
    local dest=

    if [[ ${direction} == "send" ]]
    then
        src=${instigator}
    elif [[ ${direction} == "receive" ]]
    then
        src=${responder}
    else
        log_error "Only 'send' or 'receive' supported"
        return 1
    fi

    root_path=$(getRootPath ${src})
    namespace=$(getNamespace ${src})
    pod=$(getPod ${src})

    local filename="${root_path}$(getTestFileName ${name})"

    log_info "Preparing file for transmission: ${filename} ${namespace} ${pod}"
    echo "echo '$content' > ${filename}" | oc rsh -n ${namespace} ${pod}
    [[ $? != 0 ]] && { log_error "Failed to place file in pod: ${namespace}/${pod}"; return 1; }
    echo "$content"
    LOG_EXIT
}

function prepare_dest()
{
    LOG_ENTRY
    local basedir=$1
    local namespace=$2
    local pod=$3
    local result=

    log_info "Preparing Dest: ${namespace} ${pod} ${basedir}"

    echo "rm -f ${basedir}/in/*" | oc rsh -n ${namespace} ${pod}
    [[ $? != 0 ]] && { log_error "Failed to prepare pod: ${namespace}/${pod}"; return 1; }
    LOG_EXIT
}

function prepare_test()
{
    local name=$1
    local instigator=$2
    local responder=$3
    local direction=$4

    local dest=

    if [[ ${direction} == "send" ]]
    then
        dest=${responder}
    elif [[ ${direction} == "receive" ]]
    then
        dest=${instigator}
    else
        log_error "Only 'send' or 'receive' supported"
        return 1
    fi

    local root_path=$(getRootPath ${dest})
    local namespace=$(getNamespace ${dest})
    local asperapod=$(getPod ${dest})

    oc_login "${dest}" || { return 1; }
    prepare_dest "${root_path}" "${namespace}" "${asperapod}"
}

function pull_content()
{
    LOG_ENTRY
    local name=$1
    local instigator=$2
    local responder=$3
    local direction=$4

    local filename=$(getResultFileName $name)
    local dest=

    if [[ ${direction} == "send" ]]
    then
        dest=${responder}
    elif [[ ${direction} == "receive" ]]
    then
        dest=${instigator}
    else
        log_error "Only 'send' or 'receive' supported (${name})"
        return 1
    fi

    local root_path=$(getRootPath ${dest})
    local namespace=$(getNamespace ${dest})
    local pod=$(getPod ${dest})

    oc_login ${dest}
    log_info "Getting file: ${root_path}${filename} at ${namespace} ${pod} on $(current_host)"
    echo "cat ${root_path}${filename}" | oc rsh -n ${namespace} ${pod}
    LOG_EXIT
}

function get_json()
{
    [[ $# -lt 6 ]] && { log_error "Require at least 6 args: src_token ($1), dest_machine ($2), dest_token ($3), file ($4), ssh_port ($5) and fasp_port ($6) [optional: direction (send|receive)] in that order."; return 1; }

    local src_token=${1}
    local dest_machine=${2}
    local dest_token=${3}
    local file=$(basename ${4})
    local ssh_port=${5}
    local fasp_port=${6}
    local direction='send'

    [[ $# -gt 6 ]] && direction=${7}

    case "${direction}" in
      send)
        source_file="/out/${file}"
        dest_file="/in/${file}"
        ;;
      receive)
        source_file="/out/${file}"
        dest_file="/in/${file}"
        ;;
      *)
        log_error "Direction not supported: ${direction}"
        return 1
    esac

    echo "'"$(printf '{"direction":"%s","remote_host":"%s","remote_user":"%s","remote_password":"%s","token":"Basic %s","fasp_port":%s,"ssh_port":%s,"paths":[{"source":"%s","destination":"%s"}]}' \
 ${direction} ${dest_machine} ${ASPERA_USER} ${ASPERA_PASSWORD} ${dest_token} ${fasp_port} ${ssh_port} ${source_file} ${dest_file})"'"
}

function send()
{
    LOG_ENTRY
    local name=$1
    local instigator=$2
    local responder=$3
    local direction=$4
    local filename=$5
    local host=
    local token=

    host=$(getHost ${instigator}) || { log_error "Could not get host to send to (${name})"; return 1; }
    token=$(getToken ${instigator}) || { log_error "Could not get token to use in send (${name})"; return 1; }

    local id=
    local json=$(get_json ${token} \
                          $(getDestAddress ${responder} ${instigator}) \
                          $(getToken ${responder}) \
                          ${filename} \
                          $(getSshPort ${responder}) \
                          $(getFaspPort ${responder}) \
                          ${direction}) || \
                { log_error "Failed to set JSON payload for transfer for ${instigator}/${responder} $filename (${direction})"; return 1; }

    log_info "Sending message: Posting to ${host} (${instigator} token: ${token}) the following JSON payload:\n ${json}"

    id=$(eval $(echo curl -k -H \"Authorization: Basic ${token}\" -X POST https://${host}/ops/transfers -d ${json}) 2>/dev/null | ${JQ} '.id' | awk -F '"' '{print $2}') \
      || { log_error "Failed to post json to 'https://${host}/ops/transfers' with token '${token}' "; return 1; }

    export TX_ID=$id
    echo "$id"
    LOG_EXIT
}

function get_transfer_status()
{
    LOG_ENTRY
    local host=$1
    local token=$2
    local id=$3
    [[ -z "$id" ]] && id=$TX_ID

    curl -ki -H "Authorization: Basic ${token}" -X GET https://${host}/ops/transfers/${id} 2>/dev/null
    LOG_EXIT
}

function execute_test()
{
    LOG_ENTRY
    local name=$1
    local instigator=$2
    local responder=$3
    local direction=$4
    local file_content=
    local id=
    local root_path=
    local namespace=
    local pod=

    local filename=$(getTestFileName ${name})
    file_content=$(prepare_file ${name} ${instigator} ${responder} ${direction}) \
      || { log_error "Failed to put file for $name"; return 1; }

    id=$(send ${name} ${instigator} ${responder} ${direction} ${filename}) \
      || { log_error "Failed to send from Central to Deployed using docker net"; return 1; }

    echo "$id:$filename:$file_content"
    LOG_EXIT
}

function wait_status()
{
    local host=$1
    local token=$2
    local id=$3

    local source_path=
    local wait_time=0

    until [[ (! -z ${source_path} && ${source_path} != 'null') || ${wait_time} -eq 5 ]]
    do
      source_path=$(get_transfer_status "${host}" "${token}" "${id}" | tail -n +5 | ${JQ} '.start_spec.source_paths[0]' | sed 's/"//g')
      sleep ${wait_time}
      let wait_time=wait_time+1
    done

    [[ -z ${source_path} ]] && return 1
    return 0
}

function getRootPath()
{
    case ${1} in
      CENTRAL)
        echo ${CENTRAL_ROOT_PATH}
        ;;
      DEPLOYED)
        echo ${DEPLOYED_ROOT_PATH}
        ;;
      LOCAL_DEPLOYED)
        echo ${DEPLOYED_ROOT_PATH}
        ;;
      *)
        return 1
        ;;
    esac
}

function getNamespace()
{
    case ${1} in
      CENTRAL)
        echo ${CENTRAL_NS}
        ;;
      DEPLOYED)
        echo ${DEPLOYED_NS}
        ;;
      LOCAL_DEPLOYED)
        echo ${LOCAL_DEPLOYED_NS}
        ;;
      *)
        return 1
        ;;
    esac
}

function getToken()
{
    case ${1} in
      CENTRAL)
        echo ${CENTRAL_TOKEN}
        ;;
      DEPLOYED)
        echo ${DEPLOYED_TOKEN}
        ;;
      LOCAL_DEPLOYED)
        echo ${DEPLOYED_TOKEN}
        ;;
      *)
        return 1
        ;;
    esac
}

function getComputeNode()
{
    local target=$1
    oc_login ${target}
    oc get nodes -l "node-role.kubernetes.io/compute=true" | tail -n1 | awk '{print $1}'
}

function getDestAddress()
{
    local responder=$1
    local instigator=$2

    if [[ ${responder} == "LOCAL_DEPLOYED" || ${instigator} == "LOCAL_DEPLOYED" ]]
    then
        getPodIPAddress ${responder}
    else
        getComputeNode ${responder}
    fi
}

function getHost()
{
    oc_login ${1}
    oc get route -n $(getNamespace $1) | grep '\-aspera-api' | awk '{print $2}'
}

function getPodIPAddress()
{
    oc_login ${1}
    oc get pods -n $(getNamespace $1) -o wide | grep 'aspera.*Running' | awk '{print $6}'
}

function getPod()
{
    oc_login ${1}
    oc get pods -n $(getNamespace $1) | grep "aspera.*Running" | awk '{print $1}'
}

function getSshPort()
{
    case ${1} in
      CENTRAL)
        echo ${SSH_NODE_PORT}
        ;;
      DEPLOYED)
        echo ${SSH_NODE_PORT}
        ;;
      LOCAL_DEPLOYED)
        echo ${SSH_INTERNAL_PORT}
        ;;
      *)
        return 1
        ;;
    esac
}

function getFaspPort()
{
    case ${1} in
      CENTRAL)
        echo ${FASP_NODE_PORT}
        ;;
      DEPLOYED)
        echo ${FASP_NODE_PORT}
        ;;
      LOCAL_DEPLOYED)
        echo ${FASP_INTERNAL_PORT}
        ;;
      *)
        return 1
        ;;
    esac
}

function oc_login()
{
    local src=$1
    if [[ "${src}" == "CENTRAL" ]]
    then
        central_login
    elif [[ "${src}" == "LOCAL_DEPLOYED" ]]
    then
        central_login
    elif [[ "${src}" == "DEPLOYED" ]]
    then
        deployed_login
    else
        log_error "Not able to match a known config - instigator must be CENTRAL, DEPLOYED or LOCAL_DEPLOYED"
        return 1
    fi

}

function print_details()
{
    local name=$1
    local instigator=$2
    local responder=$3
    local direction=$4

    log_info "TEST DETAILS: ${name}"
    log_info "instigator=${instigator}"
    log_info "responder=${responder}"
    log_info "direction=${direction}"
    log_info "instigator root path=$(getRootPath ${instigator})"
    log_info "instigator namespace=$(getNamespace ${instigator})"
    log_info "instigator token=$(getToken ${instigator})"
    log_info "instigator dest addr=$(getDestAddress ${instigator})"
    log_info "instigator host=$(getHost ${instigator})"
    log_info "instigator pod ip=$(getPodIPAddress ${instigator})"
    log_info "instigator pod=$(getPod ${instigator})"
    log_info "instigator ssh port=$(getSshPort ${instigator})"
    log_info "instigator fasp port=$(getFaspPort ${instigator})"
    log_info "responder root path=$(getRootPath ${responder})"
    log_info "responder namespace=$(getNamespace ${responder})"
    log_info "responder token=$(getToken ${responder})"
    log_info "responder dest addr=$(getDestAddress ${responder})"
    log_info "responder host=$(getHost ${responder})"
    log_info "responder pod ip=$(getPodIPAddress ${responder})"
    log_info "responder pod=$(getPod ${responder})"
    log_info "responder ssh port=$(getSshPort ${responder})"
    log_info "responder fasp port=$(getFaspPort ${responder})"
}

function do_test()
{
    LOG_ENTRY
    local name=$1
    local instigator=$2
    local responder=$3
    local direction=$4
    local result=
    local id=
    local content=
    local json=
    local host=
    local token=
    local dest_root_path=
    local failed=false

    host=$(getHost ${instigator}) || { log_error "Could not get host to send to (${name})"; return 1; }
    token=$(getToken ${instigator}) || { log_error "Could not get token to use in send (${name})"; return 1; }

    log_always "TEST: $name"
    prepare_test "${name}" "${instigator}" "${responder}" "${direction}" || \
      { log_error "Failed to prepare test (${name})"; return 1; }

    result=$(execute_test ${name} ${instigator} ${responder} ${direction}) || { log_error "Failed to execute test (${name})"; return 1; }

    id=$(echo "${result}" | awk -F ':' '{print $1}')
    filename=$(basename $(echo "${result}" | awk -F ':' '{print $2}'))
    content=$(echo "${result}" | awk -F ':' '{print $3}')

    log_info "${name}: Transaction ID: $id"
    log_info "${name}: filename: $filename"
    log_info "${name}: content: $content"

    [[ -z "$id" ]] && { log_error "Failed to even transact with server"; return 1; }
    export TX_ID=$id
    wait_status ${host} ${token} ${id}

    json=$(get_transfer_status ${host} ${token} ${id} | tail -n +5)
    log_debug "Status JSON: $json"
    local tx_filepath=$(echo "${json}" | ${JQ} '.start_spec.source_paths[0]' | sed 's/"//g')
    log_info "${name}: tx_filepath: $tx_filepath"

    local tx_filename=$(basename $tx_filepath)
    log_info "${name}: tx_filename: $tx_filename"

    local tx_content=$(pull_content ${name} ${instigator} ${responder} ${direction})
    log_info "${name}: tx_content: $tx_content"

    log_info "Use 'get_transfer_status ${host} ${token} ${id}' to obtain updates on transaction status"
    [[ "$filename" != "$tx_filename" ]] && { failed=true; log_fail "${name}: File names not the same: $filename != $tx_filename"; }
    [[ "$content" != "$tx_content" ]]   && { failed=true; log_fail "${name}: File content not the same: $content != $tx_content"; }

    ! ${failed} && log_pass "${name}"
    LOG_EXIT
}

function run_tests()
{
    for ((i = 0; i < ${#TESTS[@]}; i++))
    do
        do_test ${TESTS[$i]} || { print_details ${TESTS[$i]}; return 1; }
    done
}

function executeScript()
{
    run_tests
}

wrapper
