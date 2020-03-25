#!/usr/bin/env bash
# Helper for building the amq broker, interconnect and aspera applications
#
# To build a series of AMQ broker instances:
#   export TARGET='"CENTRAL","TEST101","TEST102"'
#   ./build.sh -f amq_broker
# To build a series of AMQ Interconnect instances:
#   export TARGET='"MESH","CENTRAL","TEST101","TEST102"'
#   ./build.sh -f amq_interconnect
# To build a series of Aspera instances:
#   export TARGET='"CENTRAL","TEST101","TEST102"'
#   ./build.sh -f aspera
#
# To build series of all three instances:
#   export AMQ_TARGET='"CENTRAL","TEST101","TEST102"'
#   export IC_TARGET='"MESH","CENTRAL","TEST101","TEST102"'
#   export ASPERA_TARGET='"CENTRAL","TEST101","TEST102"'
#   ./build.sh

ADDITONAL_ARGS_PATTERN='+(-t|--target|-i|--inventory|-p|--passphrase|-x|--extra-vars|--tags|--skip-tags|--tasks|--oc-login-url|--registry-server)'
ADDITONAL_SWITCHES_PATTERN='+(--dry-run)'

source "$(dirname ${BASH_SOURCE[0]})/wrapper.sh"
source "$(dirname ${BASH_SOURCE[0]})/common-properties.sh"

SECRET_FILE=~/.mjdisecrets

TAGS=
SKIP_TAGS=
EXTRA_VARS=
CREDENTIAL_VAULT=
SELECTED_TASKS=
OC_LOGIN_URL=
INVENTORY=
REGISTRY_SERVER=

DRY_RUN=false
REQUIRED_CREDENTIALS=(unlock_git_cred unlock_app_cred unlock_ocp_cred)
GIT_URL=${HOME}/code/ar_osc # Default to a local path rather than URL

[[ -z "$ENV_NAME" ]]         && ENV_NAME=DEV                                      # The environment name
[[ -z "$ENV_GIT_REPO_URL" ]] && ENV_GIT_REPO_URL=${GIT_URL}/osc_environments.git  # The URL to the Environment Data Store
[[ -z "$ENV_GIT_REPO" ]]     && ENV_GIT_REPO=${ENV_GIT_REPO_URL}                  # The Environment Data Store (defaults to ENV_GIT_REPO_URL but can be a path, e.g. ${HOME}/code/ar_osc/osc_environments)

function extraArgsClause() {
    local result=""
    if [[ ! -z "$EXTRA_VARS" ]]
    then
        for entry in $(echo "$EXTRA_VARS" | sed 's/,/ /g')
        do
            result="${result} --extra-vars '${entry}'"
        done
    fi
    echo "$result"
}

function getTargetsAsJsonArray()
{
    local result='{"targets": ['
    local entry=
    if [[ -n "${TARGET}" ]]
    then
        for entry in $(echo ${TARGET} | sed "s/,/ /g")
        do
            result="${result}\"${entry}\","
        done
        result="${result::-1}]}"
    fi
    echo -e "${result}"
}

function getAbsFileName()
{
    echo "$(cd $(dirname ${1}); pwd)/$(basename ${1})"
}

function playbookDir()
{
    getAbsFileName "${SOURCE_PATH}/../playbooks"
}

function vaultClause()
{
    local result=
    local cred=
    for cred in ${REQUIRED_CREDENTIALS[@]}
    do
        [[ -f ~/.vaults/${cred}.txt ]] || { log_error "Vault file not found: ~/.vaults/${cred}.txt"; return 1; }
        result="${result} --vault-id ${cred}@~/.vaults/${cred}.txt"
    done
    echo ${result}
}

function createPassphraseFiles()
{
    local result=
    local cred=
    for cred in ${REQUIRED_CREDENTIALS[@]}
    do
        echo "$(getSecret ${cred})" > ~/.vaults/${cred}.txt
        chmod 600 ~/.vaults/${cred}.txt
        addTempFiles ~/.vaults/${cred}.txt
    done
}

function executeAnsiblePlaybook()
{
    local playbook="$1"
    local trap_clause="trap 'rm -f ${TEMP_FILES}' SIGINT ;"
    local result=

    ensureSecrets         || { log_error "Failed establish all secrets"; return 1; }
    createPassphraseFiles || { log_error "Failed to store credentials";  return 1; }

    local command="ansible-playbook"

    [[ -n ${INVENTORY} ]]        && command="$command -i ${INVENTORY}"
    [[ -n ${ENV_NAME} ]]         && command="$command --extra-vars 'environment_name=${ENV_NAME}'"
    [[ -n ${ENV_GIT_REPO} ]]     && command="$command --extra-vars 'git_repo_url=${ENV_GIT_REPO}'"
    [[ -n ${CREDENTIAL_VAULT} ]] && command="$command --extra-vars 'credential_vault=${CREDENTIAL_VAULT}'"
    [[ -n ${SELECTED_TASKS} ]]   && command="$command --extra-vars 'selected_tasks=${SELECTED_TASKS}'"
    [[ -n ${OC_LOGIN_URL} ]]     && command="$command --extra-vars 'oc_login_url=${OC_LOGIN_URL}'"
    [[ -n ${TARGET} ]]           && command="$command --extra-vars '$(getTargetsAsJsonArray)'"

    command="$command $(extraArgsClause)" # any additional extra vars

    [[ -n "${TAGS}" ]]           && command="$command --tags ${TAGS}"
    [[ -n "${SKIP_TAGS}" ]]      && command="$command --skip-tags ${SKIP_TAGS}"

    command="$command $(vaultClause) ${playbook}"

    local _command=$(echo "${command}" | tr -s ' ')

    log_info "${_command}"

    if ! $DRY_RUN
    then
        eval "echo \"${trap_clause}${_command}\" | /bin/bash"
    fi

    result=$?
    return ${result}
}

function updateRegistryCerts()
{
    REQUIRED_CREDENTIALS=(unlock_ocp_cred)
    ENV_GIT_REPO=
    ENV_NAME=
    EXTRA_VARS="${EXTRA_VARS},target=${TARGET}"
    TARGET=
    executeAnsiblePlaybook "$(playbookDir)/update-registry-certs.yml"
}

function addRegistrySecret()
{
    REQUIRED_CREDENTIALS=(unlock_git_cred unlock_ocp_cred)
    ENV_GIT_REPO=
    ENV_NAME=
    EXTRA_VARS="${EXTRA_VARS},registry_server=${REGISTRY_SERVER}"
    EXTRA_VARS="${EXTRA_VARS},registry_secret_namespace=${TARGET}"
    TARGET=
    executeAnsiblePlaybook "$(playbookDir)/add-registry-secret.yml"
}

function setup_tls()
{
    REQUIRED_CREDENTIALS=(unlock_git_cred)
    executeAnsiblePlaybook "$(playbookDir)/setup-tls.yml"
}

function removeCA()
{
    REQUIRED_CREDENTIALS=(unlock_git_cred)
    EXTRA_VARS="${EXTRA_VARS},remove_ca=true"
    executeAnsiblePlaybook "$(playbookDir)/remove-ca.yml"
}

function generate_secrets()
{
    REQUIRED_CREDENTIALS=(unlock_git_cred unlock_app_cred)
    EXTRA_VARS="${EXTRA_VARS},app_vault_passphrase=$(getSecret unlock_app_cred)"
    executeAnsiblePlaybook "$(playbookDir)/generate-secrets.yml"
}

function resetSecrets()
{
    REQUIRED_CREDENTIALS=(unlock_git_cred unlock_app_cred)
    EXTRA_VARS="${EXTRA_VARS},reset_secrets=true"
    executeAnsiblePlaybook "$(playbookDir)/reset-secrets.yml"
}

function prepare()
{
    REQUIRED_CREDENTIALS=(unlock_git_cred unlock_app_cred)
    executeAnsiblePlaybook "$(playbookDir)/prepare.yml"
}

function amq_broker()
{
    executeAnsiblePlaybook "$(playbookDir)/amq-broker.yml"
}

function amq_interconnect()
{
    executeAnsiblePlaybook "$(playbookDir)/amq-interconnect.yml"
}

function aspera()
{
    executeAnsiblePlaybook "$(playbookDir)/aspera.yml"
}

function login()
{
    REQUIRED_CREDENTIALS=(unlock_git_cred unlock_ocp_cred)
    executeAnsiblePlaybook "$(playbookDir)/openshift-login.yml"
}

function showB64EncodedFile()
{
    local theFile=${1}
    ENV_GIT_REPO=
    ENV_NAME=
    REQUIRED_CREDENTIALS=()
    EXTRA_VARS="${EXTRA_VARS},thefile=${theFile}"
    executeAnsiblePlaybook "$(playbookDir)/show-b64encoded-file.yml"
}

function showB64DecodedFile()
{
    local theFile=${1}
    ENV_GIT_REPO=
    ENV_NAME=
    REQUIRED_CREDENTIALS=()
    EXTRA_VARS="${EXTRA_VARS},thefile=${theFile}"
    executeAnsiblePlaybook "$(playbookDir)/show-b64decoded-file.yml"
}

function testEnvOps()
{
    REQUIRED_CREDENTIALS=(unlock_git_cred unlock_app_cred)
    executeAnsiblePlaybook "$(playbookDir)/test-env-ops.yml"
}

function overwrite()
{
    local secret=$1
    local result=0
    if haveSecret $secret
    then
        log_always "The secret '$secret' already exists. Overwrite? [y/n]"
        ! confirmed && result=1
    fi
    return $result
}

########################################################################################################################
# Ensure required secrets are setup
########################################################################################################################
function ensureSecrets()
{
    LOG_ENTRY
    local cred=
    local result=
    for cred in ${REQUIRED_CREDENTIALS[@]}
    do
        log_debug "Checking if secrete exists: ${cred}"
        haveSecret "${cred}"
        result=$?
        [[ $result == 2 ]] && { log_error "Cannot ensure secrets"; return 1; }
        [[ $result == 0 ]] || storeSecret "${cred}"
    done
    LOG_EXIT
}

########################################################################################################################
# Setup or overwrite current secrets
#  i.e. ./build.sh -f setupSecrets
########################################################################################################################
function setupSecrets()
{
    local cred=
    for cred in ${REQUIRED_CREDENTIALS[@]}
    do
        overwrite "${cred}" && storeSecret "${cred}"
    done
}

function usage()
{
  log_always "Usage: $0 -t <comma separated list of targets> [optional: -i <inventory> -p <secret passphrase>]"
}

function executeScript()
{
    _TARGET=$TARGET
    prepare          || { log_error "Failed to prepare env ($ENV_NAME)"; return 1; }

    [[ -n "$AMQ_TARGET" ]] && TARGET=$AMQ_TARGET
    amq_broker       || { log_error "Failed to deploy amq_broker on $TARGET"; return 1; }

    TARGET=$_TARGET
    [[ -n "$IC_TARGET" ]] && TARGET=$IC_TARGET
    amq_interconnect || { log_error "Failed to deploy amq_interconnect on $TARGET"; return 1; }

    TARGET=$_TARGET
    [[ -n "$ASPERA_TARGET" ]] && TARGET=$ASPERA_TARGET
    aspera           || { log_error "Failed to deploy aspera on $TARGET"; return 1; }
}

function extractArgs()
{
    local arg_key=
    local optarg=
    while [[ $# -gt 0 ]]
    do
      arg_key="$1"
      optarg=
      if [ $# -gt 1 ]
      then
        optarg="$2"
      fi
      case ${arg_key} in
        -t|--target)
            setOption "${arg_key}" "TARGET" "$(echo "${optarg}" | tr ',' ' ')"
            shift # past argument
            ;;
        -i|--inventory)
            setOption "${arg_key}" "INVENTORY" "${optarg}"
            shift # past argument
            ;;
        -c|--credential-vault)
            setOption "${arg_key}" "CREDENTIAL_VAULT" "${optarg}"
            shift # past argument
            ;;
        -x|--extra-vars)
            setOption "${arg_key}" "EXTRA_VARS" "${optarg}"
            shift # past argument
            ;;
        --tags)
            setOption "${arg_key}" "TAGS" "${optarg}"
            shift # past argument
            ;;
        --tasks)
            setOption "${arg_key}" "SELECTED_TASKS" "${optarg}"
            shift # past argument
            ;;
        --skip-tags)
            setOption "${arg_key}" "SKIP_TAGS" "${optarg}"
            shift # past argument
            ;;
        --oc-login-url)
            setOption "${arg_key}" "OC_LOGIN_URL" "${optarg}"
            shift # past argument
            ;;
        --registry-server)
            setOption "${arg_key}" "REGISTRY_SERVER" "${optarg}"
            shift # past argument
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
      esac
      shift # past argument or value
    done

    APP_CREDENTIAL_FILE=".a$$"
    OPENSHIFT_CREDENTIAL_FILE=".o$$"
    addTempFiles "${APP_CREDENTIAL_FILE}"
    addTempFiles "${OPENSHIFT_CREDENTIAL_FILE}"

    return 0
}

wrapper
