#!/usr/bin/env bash
# Helper for building the amq broker, interconnect and aspera applications
#

ADDITONAL_ARGS_PATTERN='+(-t|--target|-i|--instances|-p|--passphrase|-x|--extra-vars|--tags|--skip-tags)'
ADDITONAL_SWITCHES_PATTERN='+(-s|--suppresscheckin)'

source "$(dirname ${BASH_SOURCE[0]})/wrapper.sh"
source "$(dirname ${BASH_SOURCE[0]})/common-properties.sh"

SECRET_FILE=~/.mjdisecrets

TAGS=
SKIP_TAGS=
CHECKIN=true
EXTRA_VARS=
CREDENTIAL_VAULT=

function getMjdiVaultPassphrase() {
    getSecret 'mjdi_passphrase'
}

function getOpenshiftCredentialVaultPassphrase() {
    getSecret 'openshift_credentials_passphrase'
}

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
    result="${result}\"${TARGET}\"]}"
    echo -e "${result}"
}

function getTargetsAsString()
{
    echo "${TARGET}"
}

function getTargetsAsLowercase()
{
    echo "$TARGET" | tr '[:upper:]' '[:lower:]'
}

function getTargetSeedHosts()
{
    echo "seed-hosts"
}

function getAbsFileName()
{
    echo "$(cd $(dirname ${1}); pwd)/$(basename ${1})"
}

function playbookDir()
{
    getAbsFileName "${SOURCE_PATH}/../playbooks"
}

function getAppDefFile()
{
    [[ -f "${INSTANCES}" ]] && { getAbsFileName ${INSTANCES}; return 0; }
    [[ -f "varfiles/${INSTANCES}.yml" ]] && { getAbsFileName varfiles/${INSTANCES}.yml; return 0; }
}

function getDeploymentPhase()
{
    egrep "^deployment_phase:[[:space:]]*'[A-Z0-9]*'" $(getAppDefFile) | awk -F "'" '{print $2}'
}

function getGeneratedDir()
{
     echo "/apps/osc_environments/$(getDeploymentPhase)/generated"
}

function getInventoryPath()
{
    local app_instance_name=$1
    local app_name=$2

    echo "$(getGeneratedDir)/${app_instance_name}/${app_name}/inventory"
}

function vaultFile()
{
    # This is now defaulted in the ansible playbooks to the same
    echo $(getGeneratedDir)/mjdi.vault
}

function executeCommand()
{
    local cmd="$1"
    local trap_clause=""
    local tag_clause=""
    local result=
    [[ ! -z "${APP_CREDENTIAL_FILE}" ]] && trap_clause="trap 'rm -f ${APP_CREDENTIAL_FILE} ${OPENSHIFT_CREDENTIAL_FILE}' SIGINT ;"
    [[ ! -z "${TAGS}" ]] && tag_clause=" --tags ${TAGS}"
    [[ ! -z "${SKIP_TAGS}" ]] && skip_tag_clause=" --skip-tags ${SKIP_TAGS}"

    log_info "Command: ${cmd}${tag_clause}"

    # Create the temp passphrase files
    echo "$(getMjdiVaultPassphrase)" > "${APP_CREDENTIAL_FILE}" || { log_error "Failed to store app credential"; return 1; }
    echo "$(getOpenshiftCredentialVaultPassphrase)" > "${OPENSHIFT_CREDENTIAL_FILE}" || { log_error "Failed to store openshift credential"; return 1; }
    chmod 600 ${APP_CREDENTIAL_FILE} ${OPENSHIFT_CREDENTIAL_FILE}

    local command=$cmd
    [[ -e ${CREDENTIAL_VAULT} ]] && command="$cmd --extra-vars \"@${CREDENTIAL_VAULT}\""

    eval "echo \"${trap_clause}${command}${tag_clause}${skip_tag_clause}\" | /bin/bash"
    result=$?
    rm -f ${APP_CREDENTIAL_FILE} ${OPENSHIFT_CREDENTIAL_FILE}
    return ${result}
}

function setup_tls()
{
    local cmd="ansible-playbook $(playbookDir)/setup-tls.yml \
      --extra-vars \"app_instances_file=$(getAppDefFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' $(extraArgsClause)"
    executeCommand "$cmd"
}

function generate_secrets()
{
    local cmd="ansible-playbook $(playbookDir)/generate-secrets.yml \
      --extra-vars \"app_vault_passphrase=$(getMjdiVaultPassphrase)\" \
      --extra-vars \"app_instances_file=$(getAppDefFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' $(extraArgsClause)"
    executeCommand "$cmd"
}

function checkin()
{
    local cmd="ansible-playbook $(playbookDir)/git-checkin.yml \
      --extra-vars \"app_vault_passphrase=$(getMjdiVaultPassphrase)\" \
      --extra-vars \"app_instances_file=$(getAppDefFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' $(extraArgsClause)"
    executeCommand "$cmd"
}

function amq_broker()
{
    local cmd="ansible-playbook $(playbookDir)/amq-broker.yml -i $(getInventoryPath "$(getTargetsAsLowercase)" 'amqbroker') \
      --extra-vars \"target_seed_hosts=$(getTargetSeedHosts)\" \
      --extra-vars \"app_instances_file=$(getAppDefFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' --vault-id appcred@${APP_CREDENTIAL_FILE} $(extraArgsClause)"
    executeCommand "$cmd"
}

function amq_interconnect()
{
    local cmd="ansible-playbook $(playbookDir)/amq-interconnect.yml -i $(getInventoryPath "$(getTargetsAsLowercase)" 'amqinterconnect') \
      --extra-vars \"target_seed_hosts=$(getTargetSeedHosts)\" \
      --extra-vars \"app_instances_file=$(getAppDefFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' --vault-id appcred@${APP_CREDENTIAL_FILE} $(extraArgsClause)"
    executeCommand "$cmd"
}

function aspera()
{
    local cmd="ansible-playbook $(playbookDir)/aspera.yml -i $(getInventoryPath "$(getTargetsAsLowercase)" 'aspera') \
      --extra-vars \"target_seed_hosts=$(getTargetSeedHosts)\" \
      --extra-vars \"app_instances_file=$(getAppDefFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' --vault-id appcred@${APP_CREDENTIAL_FILE} $(extraArgsClause)"
    executeCommand "$cmd"
}

function login()
{
    local cmd="ansible-playbook $(playbookDir)/openshift-login.yml \
      --extra-vars '$(getTargetsAsJsonArray)' \
      --extra-vars \"app_instances_file=$(getAppDefFile)\" \
      --vault-id appcred@${APP_CREDENTIAL_FILE} --vault-id occred@${OPENSHIFT_CREDENTIAL_FILE} $(extraArgsClause)"
    executeCommand "$cmd"
}

function executeScript()
{
    amq_broker       || { log_error "Failed to deploy amq_broker on $TARGET"; return 1; }
    amq_interconnect || { log_error "Failed to deploy amq_interconnect on $TARGET"; return 1; }
    aspera           || { log_error "Failed to deploy aspera on $TARGET"; return 1; }
    checkin          || { log_error "Failed to checkin changes for $TARGET"; return 1;}
}

# Must be manually executed using '-f'
function prepare()
{
    setup_tls        || { log_error "Failed to setup TLS"; return 1; }
    generate_secrets || { log_error "Failed to generate secrets"; return 1; }
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
# Call this function once to setup the required secrets
#  i.e. ./build.sh -f setupSecrets
########################################################################################################################
function setupSecrets()
{
    overwrite "mjdi_passphrase"                   && storeSecret "mjdi_passphrase"
    overwrite "openshift_credentials_passphrase"  && storeSecret "openshift_credentials_passphrase"
}

function usage()
{
  log_always "Usage: $0 -t <comma separated list of targets> -i <instances file> -p <secret passphrase>"
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
        -i|--instances)
            setOption "${arg_key}" "INSTANCES" "${optarg}"
            shift # past argument
            ;;
        -c|--credential-vault)
            setOption "${arg_key}" "CREDENTIAL_VAULT" "${optarg}"
            shift # past argument
            ;;
        -s|--suppresscheckin)
            CHECKIN=false
            ;;
        -x|--extra-vars)
            setOption "${arg_key}" "EXTRA_VARS" "${optarg}"
            shift # past argument
            ;;
        --tags)
            setOption "${arg_key}" "TAGS" "${optarg}"
            shift # past argument
            ;;
        --skip-tags)
            setOption "${arg_key}" "SKIP_TAGS" "${optarg}"
            shift # past argument
            ;;
      esac
      shift # past argument or value
    done

    APP_CREDENTIAL_FILE=".a$$"
    OPENSHIFT_CREDENTIAL_FILE=".o$$"
    addTempFiles "${APP_CREDENTIAL_FILE}"
    addTempFiles "${OPENSHIFT_CREDENTIAL_FILE}"

    [[ -z "${TARGET}" ]] && { log_error "Require a comma separated list (-t)"; return 1; }
    [[ -z "${INSTANCES}" ]] && { log_error "Require an instances filename (-i)"; return 1; }

    return 0
}

wrapper
