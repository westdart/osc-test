#!/usr/bin/env bash
# Helper for building the amq broker and interconnect applications
#

ADDITONAL_ARGS_PATTERN='+(-t|--target|-i|--instances|-p|--passphrase|-x|--extra-vars|--tags|--skip-tags)'
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
    [[ ! -z "${PASSWORD_FILE}" ]] && trap_clause="trap 'rm -f ${PASSWORD_FILE}' SIGINT ;"
    [[ ! -z "${TAGS}" ]] && tag_clause=" --tags ${TAGS}"
    [[ ! -z "${SKIP_TAGS}" ]] && skip_tag_clause=" --skip-tags ${SKIP_TAGS}"

    log_info "Command: ${cmd}${tag_clause}"

    eval "echo \"${trap_clause}${cmd}${tag_clause}${skip_tag_clause}\" | /bin/bash"
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
      --extra-vars \"amq_vault_passphrase=${PASSPHRASE}\" \
      --extra-vars \"app_instances_file=$(getAppDefFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' $(extraArgsClause)"
    executeCommand "$cmd"
}

function checkin()
{
    local cmd="ansible-playbook $(playbookDir)/git-checkin.yml \
      --extra-vars \"amq_vault_passphrase=${PASSPHRASE}\" \
      --extra-vars \"app_instances_file=$(getAppDefFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' $(extraArgsClause)"
    executeCommand "$cmd"
}

function amq_broker()
{
    local cmd="ansible-playbook $(playbookDir)/amq-broker.yml -i $(getInventoryPath "$(getTargetsAsLowercase)" 'amqbroker') \
      --extra-vars \"target_seed_hosts=$(getTargetSeedHosts)\" \
      --extra-vars \"app_instances_file=$(getAppDefFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' --vault-id psp@${PASSWORD_FILE} $(extraArgsClause)"
    executeCommand "$cmd"
}

function amq_interconnect()
{
    local cmd="ansible-playbook $(playbookDir)/amq-interconnect.yml -i $(getInventoryPath "$(getTargetsAsLowercase)" 'amqinterconnect') \
      --extra-vars \"target_seed_hosts=$(getTargetSeedHosts)\" \
      --extra-vars \"app_instances_file=$(getAppDefFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' --vault-id psp@${PASSWORD_FILE} $(extraArgsClause)"
    executeCommand "$cmd"
}

function aspera()
{
    local cmd="ansible-playbook $(playbookDir)/aspera.yml -i $(getInventoryPath "$(getTargetsAsLowercase)" 'aspera') \
      --extra-vars \"target_seed_hosts=$(getTargetSeedHosts)\" \
      --extra-vars \"app_instances_file=$(getAppDefFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' --vault-id psp@${PASSWORD_FILE} $(extraArgsClause)"
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

    [[ -z "${INSTANCES}" ]] && { log_error "Require an instances filename (-i)"; return 1; }

    [[ -z "${PASSPHRASE}" ]] && { log_error "Require an passphrase (-p)"; return 1; }

    PASSWORD_FILE=".p$$"
    echo "${PASSPHRASE}" > "${PASSWORD_FILE}"
    addTempFiles "${PASSWORD_FILE}"

    return 0
}


wrapper
