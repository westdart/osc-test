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
#         <test-name> <dest-prep-function> <test-function> <status-function> <pull-function>
#         Where:
#           test-name: Name of test - single string
#           dest-prep-function: Function used to prepare the destination
#           test-function: The function used to do the actual test (including setting up initial state at src)
#           status-function: Function used to obtain the status of a transfer
#           pull-function: Function used to pull content from the destination for verification
#
# Functions:
#   central_login()                : Login to the Central Cluster console
#   deployed_login()               : Login to the Deployed Cluster console
#   os_logout()                    : Logout of whichever console that is logged in
#   setup_central_env()
#   setup_deployed_env()
#
#   prepare_file()                 : Create a file on the src to send (i.e. into the 'out' dir)
#   prepare_dest()                 : Generic function to clear out an 'in' folder on the destination
#   prepare_central_dest()         : Clear out the Central dest system (i.e. remove everything in the 'in' folder)
#   prepare_deployed_dest()        : Clear out the Deployed dest system (i.e. remove everything in the 'in' folder)
#   prepare_local_dest()           : Clear out the Deployed dest system (i.e. remove everything in the 'in' folder)
#
#   send()                         : Generic function to send a file from src to dest
#   do_central_send()              : Instigate sending a file from Central to Deployed
#   do_central_send_local()        : Instigate sending a file from Central to a Deployed in same cluster
#   do_deployed_send()             : Instigate sending a file from Deployed to Central
#   do_local_send()                : Instigate sending a file from a Deployed in the same cluster to Central
#
#   get_transfer_status()          : Generic function to get the transfer status of a transaction
#   get_central_transfer_status()  : Get the status of a central file transfer
#   get_deployed_transfer_status() : Get the status of a deployed file transfer
#   get_local_deployed_transfer_status()
#                                  : Get the status of a deployed file transfer from within same cluster as Central
#
#   pull_content()                 : Generic function to obtain file content of a transferred file
#   pull_content_central()         : Obtain file content of a transferred file to Central
#   pull_content_deployed()        : Obtain file content of a transferred file to Deployed
#   pull_content_local()           : Obtain file content of a transferred file to Deployed co-located with Central
#
#   get_json()                     : Generic function to create a json payload
#   get_json_central_to_deployed() : Create a json payload for sending a file to Deployed from Central
#   get_json_central_to_deployed_using_docker_net()
#                                  : Create a json payload for sending a file to Deployed from Central in same cluster
#   get_json_deployed_to_central() : Create a json payload for sending a file to Central from Deployed
#   get_json_deployed_to_central_using_docker_net()
#                                  : Create a json payload for sending a file to Central from Deployed in same cluster
#
#   execute_test()                 : Execute a test
#   do_test()                      : Wrapper for test execution and verification
#   run_tests()                    : Loop over all tests and execute
#

source "$(dirname ${BASH_SOURCE[0]})/logger.sh"

TESTS=(
    "aspera_test_central_send       prepare_deployed_dest do_central_send       get_central_transfer_status        pull_content_deployed"
    "aspera_test_deployed_send      prepare_central_dest  do_deployed_send      get_deployed_transfer_status       pull_content_central"
    "aspera_test_central_send_local prepare_local_dest    do_central_send_local get_central_transfer_status        pull_content_local"
    "aspera_test_local_send         prepare_central_dest  do_local_send         get_local_deployed_transfer_status pull_content_central"
)

shopt -s expand_aliases
RED='\033[1;31m'
NC='\033[0m' # No Color

export CENTRAL_CONSOLE_URL="https://$(grep t1.master /etc/hosts | awk '{print $NF}'):8443"
export DEPLOYED_CONSOLE_URL="https://$(grep t2.master /etc/hosts | awk '{print $NF}'):8443"
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
export ASPERA_PASSWORD=GFQDprRXGwGkPNeIbdadpoHaz

function central_login()
{
    log_info "Logging into ${CENTRAL_CONSOLE_URL} as ${CENTRAL_CONSOLE_USER} (may require a password ...)"
    oc login ${CENTRAL_CONSOLE_URL} -u ${CENTRAL_CONSOLE_USER} -p ${CENTRAL_CONSOLE_PASSWORD} &> /dev/null
}

function deployed_login()
{
    log_info "Logging into ${DEPLOYED_CONSOLE_URL} as ${DEPLOYED_CONSOLE_USER} (may require a password ...)"
    oc login ${DEPLOYED_CONSOLE_URL} -u ${DEPLOYED_CONSOLE_USER} -p ${DEPLOYED_CONSOLE_PASSWORD} &> /dev/null
}

function os_logout()
{
    oc logout &> /dev/null
}

function setup_central_env()
{
    central_login
    export CENTRAL_HOST=$(oc get route -n ${CENTRAL_NS} | grep '\-aspera-api' | awk '{print $2}')
    export CENTRAL_DEPLOYED_FILE=centralToDeployedFile.txt
    export ASPERA_CENTRAL_POD=$(oc get pods -n ${CENTRAL_NS} | grep "aspera.*Running" | awk '{print $1}')
    echo "touch /desbs/stg/out/${CENTRAL_DEPLOYED_FILE}" | oc rsh -n ${CENTRAL_NS} ${ASPERA_CENTRAL_POD}
    export CENTRAL_SSH_PORT=30001
    export CENTRAL_FASP_PORT=30002
    export CENTRAL_COMPUTE_NODE=$(oc get nodes -l "node-role.kubernetes.io/compute=true" | tail -n1 | awk '{print $1}')

    export LOCAL_DEPLOYED_HOST=$(oc get route -n ${LOCAL_DEPLOYED_NS} | grep '\-aspera-api' | awk '{print $2}')
    export ASPERA_LOCAL_DEPLOYED_POD=$(oc get pods -n ${LOCAL_DEPLOYED_NS} | grep "aspera.*Running" | awk '{print $1}')
    export LOCAL_CENTRAL_FILE=localDeployedToCentralFile.txt
}

function setup_deployed_env()
{
    deployed_login
    export DEPLOYED_HOST=$(oc get route -n ${DEPLOYED_NS} | grep '\-aspera-api' | awk '{print $2}')
    export DEPLOYED_CENTRAL_FILE=deployedToCentralFile.txt
    export ASPERA_DEPLOYED_POD=$(oc get pods -n ${DEPLOYED_NS} | grep "aspera.*Running" | awk '{print $1}')
    echo "touch /mjdi/local/GFT/out/${DEPLOYED_CENTRAL_FILE}" | oc rsh -n ${DEPLOYED_NS} ${ASPERA_DEPLOYED_POD}
    export DEPLOYED_SSH_PORT=30001
    export DEPLOYED_FASP_PORT=30002
    export DEPLOYED_COMPUTE_NODE=$(oc get nodes -l "node-role.kubernetes.io/compute=true" | tail -n1 | awk '{print $1}')
}

function basic_tests()
{
    # Basic tests
    echo "/opt/aspera/bin/asnodeadmin -l" | oc rsh -n ${CENTRAL_NS} ${ASPERA_CENTRAL_POD}
    echo "/opt/aspera/bin/asnodeadmin -l" | oc rsh -n ${DEPLOYED_NS} ${ASPERA_CENTRAL_POD}

    # Browse
    printf "\n${RED}Browse of ${CENTRAL_HOST}${NC}\n"
    curl -ki -H "Authorization: Basic ${CENTRAL_TOKEN}" -d '{"filters":{"basenames":["*File*.txt"],"types":["file","directory"]},"path":"/out","sort":"mtime_a"}' https://${CENTRAL_HOST}/files/browse
    printf "\n${RED}Browse of ${DEPLOYED_HOST}${NC}\n"
    curl -ki -H "Authorization: Basic ${DEPLOYED_TOKEN}" -d '{"filters":{"basenames":["*File*.txt"],"types":["file","directory"]},"path":"/out","sort":"mtime_a"}' https://${DEPLOYED_HOST}/files/browse
    printf "\n"
    printf "\n${RED}Browse of ${LOCAL_DEPLOYED_HOST}${NC}\n"
    curl -ki -H "Authorization: Basic ${DEPLOYED_TOKEN}" -d '{"filters":{"basenames":["*File*.txt"],"types":["file","directory"]},"path":"/out","sort":"mtime_a"}' https://${LOCAL_DEPLOYED_HOST}/files/browse
    printf "\n"
}

function get_json()
{
    [[ $# != 6 ]] && { log_error "Require 6 args: src_token ($1), dest_machine ($2), dest_token ($3), file ($4), ssh_port ($5) and fasp_port ($6) in that order."; return 1; }

    local src_token=${1}
    local dest_machine=${2}
    local dest_token=${3}
    local file=$(basename ${4})
    local ssh_port=${5}
    local fasp_port=${6}

    echo "'"$(printf '{"direction":"send","remote_host":"%s","remote_user":"%s","remote_password":"%s","token":"Basic %s","fasp_port":%s,"ssh_port":%s,"paths":[{"source":"/out/%s","destination":"/in/%s"}]}' \
 ${dest_machine} ${ASPERA_USER} ${ASPERA_PASSWORD} ${dest_token} ${fasp_port} ${ssh_port} ${file} ${file})"'"
}

function get_json_central_to_deployed_using_docker_net()
{
    local filename=$1
    [[ -z "${filename}" ]] && filename=${CENTRAL_DEPLOYED_FILE}
    get_json ${CENTRAL_TOKEN} \
             $(oc get pods -n ${LOCAL_DEPLOYED_NS} -o wide | grep 'aspera.*Running' | awk '{print $6}') \
             ${DEPLOYED_TOKEN} \
             ${filename} \
             30001 \
             30002
}

function get_json_central_to_deployed()
{
    local filename=$1
    [[ -z "${filename}" ]] && filename=${CENTRAL_DEPLOYED_FILE}
    get_json ${CENTRAL_TOKEN} \
             ${DEPLOYED_COMPUTE_NODE} \
             ${DEPLOYED_TOKEN} \
             ${filename} \
             ${DEPLOYED_SSH_PORT} \
             ${DEPLOYED_FASP_PORT}
}

function get_json_deployed_to_central()
{
    local filename=$1
    [[ -z "${filename}" ]] && filename=${DEPLOYED_CENTRAL_FILE}
    get_json ${DEPLOYED_TOKEN} \
             ${CENTRAL_COMPUTE_NODE} \
             ${CENTRAL_TOKEN} \
             ${filename} \
             ${CENTRAL_SSH_PORT} \
             ${CENTRAL_FASP_PORT}
}

function get_json_deployed_to_central_using_docker_net()
{
    local filename=$1
    [[ -z "${filename}" ]] && filename=${LOCAL_CENTRAL_FILE}
    get_json ${DEPLOYED_TOKEN} \
             $(oc get pods -n ${CENTRAL_NS} -o wide | grep 'aspera.*Running' | awk '{print $6}') \
             ${CENTRAL_TOKEN} \
             ${filename} \
             30001 \
             30002
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

function prepare_file()
{
    LOG_ENTRY
    local filename=$1
    local namespace=$2
    local pod=$3
    local content=$4
    [[ -z $content ]] && content=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')

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

function prepare_central_dest()
{
    LOG_ENTRY
    setup_central_env
    prepare_dest "${CENTRAL_ROOT_PATH}" ${CENTRAL_NS} ${ASPERA_CENTRAL_POD}
    LOG_EXIT
}

function prepare_deployed_dest()
{
    LOG_ENTRY
    setup_deployed_env
    prepare_dest "${DEPLOYED_ROOT_PATH}" ${DEPLOYED_NS} ${ASPERA_DEPLOYED_POD}
    LOG_EXIT
}

function prepare_local_dest()
{
    LOG_ENTRY
    setup_central_env
    prepare_dest "${DEPLOYED_ROOT_PATH}" ${LOCAL_DEPLOYED_NS} ${ASPERA_LOCAL_DEPLOYED_POD}
    LOG_EXIT
}

function pull_content()
{
    LOG_ENTRY
    local filename=$1
    local namespace=$2
    local pod=$3

    echo "cat ${filename}" | oc rsh -n ${namespace} ${pod}
    LOG_EXIT
}

function pull_content_central()
{
    LOG_ENTRY
    setup_central_env
    log_info "pull_content ${CENTRAL_ROOT_PATH}/in/$(basename $1) ${CENTRAL_NS} ${ASPERA_CENTRAL_POD}"
    pull_content "${CENTRAL_ROOT_PATH}/in/$(basename $1)" ${CENTRAL_NS} ${ASPERA_CENTRAL_POD}
    LOG_EXIT
}

function pull_content_deployed()
{
    LOG_ENTRY
    setup_deployed_env
    pull_content "${DEPLOYED_ROOT_PATH}/in/$(basename $1)" ${DEPLOYED_NS} ${ASPERA_DEPLOYED_POD}
    LOG_EXIT
}

function pull_content_local()
{
    LOG_ENTRY
    setup_central_env
    pull_content "${DEPLOYED_ROOT_PATH}/in/$(basename $1)" ${LOCAL_DEPLOYED_NS} ${ASPERA_LOCAL_DEPLOYED_POD}
    LOG_EXIT
}

function send()
{
    LOG_ENTRY
    local jsonf=$1
    local host=$2
    local token=$3
    local filename=$4
    local id=
    local json=

    json=$(${jsonf} ${filename}) || { log_error "Failed to set JSON payload for transfer using $jsonf $filename"; return 1; }
    log_info "Posting to ${host} the following JSON payload:\n ${json}"

    id=$(eval $(echo curl -k -H \"Authorization: Basic ${token}\" -X POST https://${host}/ops/transfers -d ${json}) 2>/dev/null | jq '.id' | awk -F '"' '{print $2}') \
      || { log_error "Failed to post json to 'https://${host}/ops/transfers' with token '${token}' "; return 1; }

    export TX_ID=$id
    echo "$id"
    LOG_EXIT
}

function do_central_send_local()
{
    LOG_ENTRY
    local filename=$1
    local id=
    id=$(send "get_json_central_to_deployed_using_docker_net" ${CENTRAL_HOST} ${CENTRAL_TOKEN} ${filename}) \
      || { log_error "Failed to send from Central to Deployed using docker net"; return 1; }
    echo "$id"
    LOG_EXIT
}

function do_central_send()
{
    LOG_ENTRY
    local filename=$1
    local id=
    id=$(send "get_json_central_to_deployed" ${CENTRAL_HOST} ${CENTRAL_TOKEN} ${filename}) \
      || { log_error "Failed to send from Central to Deployed"; return 1; }
    echo "$id"
    LOG_EXIT
}

function do_deployed_send()
{
    LOG_ENTRY
    local filename=$1
    local id=
    id=$(send "get_json_deployed_to_central" ${DEPLOYED_HOST} ${DEPLOYED_TOKEN} ${filename}) \
      || { log_error "Failed to send from Central to Deployed"; return 1; }
    echo "$id"
    LOG_EXIT
}

function do_local_send()
{
    LOG_ENTRY
    local filename=$1
    local id=
    id=$(send "get_json_deployed_to_central_using_docker_net" ${LOCAL_DEPLOYED_HOST} ${DEPLOYED_TOKEN} ${filename}) \
      || { log_error "Failed to send from Central to Deployed"; return 1; }
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

function get_central_transfer_status()
{
    LOG_ENTRY
    get_transfer_status ${CENTRAL_HOST} ${CENTRAL_TOKEN} $1
    LOG_EXIT
}

function get_deployed_transfer_status()
{
    LOG_ENTRY
    get_transfer_status ${DEPLOYED_HOST} ${DEPLOYED_TOKEN} $1
    LOG_EXIT
}

function get_local_deployed_transfer_status()
{
    LOG_ENTRY
    get_transfer_status ${LOCAL_DEPLOYED_HOST} ${DEPLOYED_TOKEN} $1
    LOG_EXIT
}

function execute_test()
{
    LOG_ENTRY
    local name=$1
    local test=$2
    local file_content=
    local id=
    local root_path=
    local namespace=
    local pod=

    if echo "$name" | grep -iq "aspera_test_central"
    then
        root_path="${CENTRAL_ROOT_PATH}"
        namespace="${CENTRAL_NS}"
        pod="${ASPERA_CENTRAL_POD}"
        central_login
    elif echo "$name" | grep -iq "aspera_test_local"
    then
        root_path="${DEPLOYED_ROOT_PATH}"
        namespace="${LOCAL_DEPLOYED_NS}"
        pod="${ASPERA_LOCAL_DEPLOYED_POD}"
        central_login
    elif echo "$name" | grep -iq "aspera_test_deployed"
    then
        root_path="${DEPLOYED_ROOT_PATH}"
        namespace="${DEPLOYED_NS}"
        pod="${ASPERA_DEPLOYED_POD}"
        deployed_login
    else
        log_error "Not able to match a known config - test name should start: aspera_test_central or aspera_test_local or aspera_test_deployed"
    fi

    local filename="${root_path}/out/${name}.file"
    log_info "Preparing file for transmission: ${filename} ${namespace} ${pod}"
    file_content=$(prepare_file "${filename}" ${namespace} ${pod}) \
      || { log_error "Failed to put file for $name"; return 1; }
    id=$(${test} ${filename}) || { log_error "Failed to send file for $name"; return 1; }
    echo "$id:$filename:$file_content"
    LOG_EXIT
}

function wait_status()
{
    local status=$1
    local id=$2
    local source_path=
    local wait_time=0

    until [[ ! -z ${source_path} || ${wait_time} -eq 4 ]]
    do
      source_path=$(${status} ${id} | tail -n +5 | jq '.start_spec.source_paths[0]' | sed 's/"//g')
      sleep ${wait_time}
      let wait_time=wait_time+1
    done

    [[ -z ${source_path} ]] && return 1
    return 0
}

function do_test()
{
    LOG_ENTRY
    local name=$1
    local dest_setup=$2
    local test=$3
    local status=$4
    local pull=$5
    local result=
    local id=
    local content=
    local json=

    log_always "TEST: $name"
    ${dest_setup} || { log_error "Failed to prepare dest ($dest_setup)"; return 1; }

    result=$(execute_test ${name} ${test}) || { log_error "Failed to execute test ($test)"; return 1; }

    id=$(echo "${result}" | awk -F ':' '{print $1}')
    filename=$(basename $(echo "${result}" | awk -F ':' '{print $2}'))
    content=$(echo "${result}" | awk -F ':' '{print $3}')

    log_info "${name}: Transaction ID: $id"
    log_info "${name}: filename: $filename"
    log_info "${name}: content: $content"

    [[ -z "$id" ]] && { log_error "Failed to even transact with server"; return 1; }
    export TX_ID=$id
    wait_status

    json=$(${status} ${id} | tail -n +5)
    log_debug "Status JSON: $json"
    local tx_filepath=$(echo "${json}" | jq '.start_spec.source_paths[0]' | sed 's/"//g')
    log_info "${name}: tx_filepath: $tx_filepath"

    local tx_filename=$(basename $tx_filepath)
    log_info "${name}: tx_filename: $tx_filename"

    local tx_content=$(${pull} ${filename})
    log_info "${name}: tx_content: $tx_content"

    log_info "Use ${status} to obtain updates on transaction status"
    [[ "$filename" != "$tx_filename" ]] && log_fail "File names not the same: $filename != $tx_filename"
    [[ "$content" != "$tx_content" ]]   && log_fail "File content not the same: $content != $tx_content"
    os_logout
    LOG_EXIT
}

function run_tests()
{
    for ((i = 0; i < ${#TESTS[@]}; i++))
    do
        do_test ${TESTS[$i]} || return 1
    done
}
