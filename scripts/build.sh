#!/usr/bin/env bash
# Helper for building the amq broker and interconnect applications
#

ADDITONAL_ARGS_PATTERN='+(-t|--target|-i|--interconnects|-p|--passphrase|-x|--extra-vars|--tags|--skip-tags)'
ADDITONAL_SWITCHES_PATTERN='+(-s|--suppresscheckin)'

source "$(dirname ${BASH_SOURCE[0]})/wrapper.sh"

TAGS=
SKIP_TAGS=
CHECKIN=true
EXTRA_VARS=

function extraArgsClause() {
    [[ ! -z "$EXTRA_VARS" ]] && echo "--extra-vars '${EXTRA_VARS}'"
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
    [[ -f "${INTERCONNETS}" ]] && { getAbsFileName ${INTERCONNETS}; return 0; }
    [[ -f "varfiles/${INTERCONNETS}.yml" ]] && { getAbsFileName varfiles/${INTERCONNETS}.yml; return 0; }
}

function getDeploymentPhase()
{
    egrep "^deployment_phase:[[:space:]]*'[A-Z0-9]*'" $(getAppDefFile) | awk -F "'" '{print $2}'
}

function getGeneratedDir()
{
     echo "/apps/environments/$(getDeploymentPhase)/generated"
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
    [[ ! -z "${PASSWORD_FILE}" ]] && trap_clause="trap 'rm -f ${PASSWORD_FILE}' SIGINT ;"
    [[ ! -z "${TAGS}" ]] && tag_clause=" --tags ${TAGS}"
    [[ ! -z "${SKIP_TAGS}" ]] && skip_tag_clause=" --skip-tags ${SKIP_TAGS}"

    log_info "Command: ${cmd}${tag_clause}"

    eval "echo \"${trap_clause}${cmd}${tag_clause}${skip_tag_clause}\" | /bin/bash"
}

function setup_tls()
{
    local cmd="ansible-playbook $(playbookDir)/setup-tls.yml \
      --extra-vars \"amq_interconnect_instances_file=$(getAppDefFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' $(extraArgsClause)"
    executeCommand "$cmd"
}

function generate_secrets()
{
    local cmd="ansible-playbook $(playbookDir)/generate-secrets.yml \
      --extra-vars \"amq_vault_passphrase=${PASSPHRASE}\" \
      --extra-vars \"amq_interconnect_instances_file=$(getAppDefFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' $(extraArgsClause)"
    executeCommand "$cmd"
}

function amq_broker()
{
    local cmd="ansible-playbook $(playbookDir)/amq-broker.yml -i $(getInventoryPath "$(getTargetsAsLowercase)" 'amqbroker') \
      --extra-vars \"target_seed_hosts=$(getTargetSeedHosts)\" \
      --extra-vars \"amq_interconnect_instances_file=$(getAppDefFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' --vault-id psp@${PASSWORD_FILE} $(extraArgsClause)"
    executeCommand "$cmd"
}

function amq_interconnect()
{
    local cmd="ansible-playbook $(playbookDir)/amq-interconnect.yml -i $(getInventoryPath "$(getTargetsAsLowercase)" 'amqinterconnect') \
      --extra-vars \"target_seed_hosts=$(getTargetSeedHosts)\" \
      --extra-vars \"amq_interconnect_instances_file=$(getAppDefFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' --vault-id psp@${PASSWORD_FILE} $(extraArgsClause)"
    executeCommand "$cmd"
}

function aspera()
{
    local cmd="ansible-playbook $(playbookDir)/aspera.yml -i $(getInventoryPath "$(getTargetsAsLowercase)" 'aspera') \
      --extra-vars \"target_seed_hosts=$(getTargetSeedHosts)\" \
      --extra-vars \"amq_interconnect_instances_file=$(getAppDefFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' --vault-id psp@${PASSWORD_FILE} $(extraArgsClause)"
    executeCommand "$cmd"
}


function executeScript()
{
    local cmd="ansible-playbook $(playbookDir)/main.yml -i $(getInventoryPath "$(getTargetsAsLowercase)" 'amqbroker') \
      --extra-vars \"target_seed_hosts=$(getTargetSeedHosts)\" \
      --extra-vars \"amq_interconnect_instances_file=$(getAppDefFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' --vault-id psp@${PASSWORD_FILE} $(extraArgsClause)"
    executeCommand "$cmd"
}

function usage()
{
  log_always "Usage: $0 -t <comma separated list of targets> -i <interconnects file> -p <secret passphrase>"
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
        -i|--interconnects)
            setOption "${arg_key}" "INTERCONNETS" "${optarg}"
            shift # past argument
            ;;
        -p|--passphrase)
            setOption "${arg_key}" "PASSPHRASE" "${optarg}"
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

    [[ -z "${TARGET}" ]] && { log_error "Require a comma separated list (-t)"; return 1; }

    [[ -z "${INTERCONNETS}" ]] && { log_error "Require an interconnect filename (-i)"; return 1; }

    [[ -z "${PASSPHRASE}" ]] && { log_error "Require an passphrase (-p)"; return 1; }

    PASSWORD_FILE=".p$$"
    echo "${PASSPHRASE}" > "${PASSWORD_FILE}"
    addTempFiles "${PASSWORD_FILE}"

    return 0
}


wrapper
