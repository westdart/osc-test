#!/usr/bin/env bash
# Helper for building the amq broker and interconnect applications
#

ADDITONAL_ARGS_PATTERN='+(-t|--targets|-i|--interconnects|-p|--passphrase|-x|--extra-vars)'
ADDITONAL_SWITCHES_PATTERN='+(-s|--suppresscheckin)'

source "$(dirname ${BASH_SOURCE[0]})/wrapper.sh"

TAGS=
CHECKIN=true
EXTRA_VARS=

function extraArgsClause() {
    [[ ! -z "$EXTRA_VARS" ]] && echo "--extra-vars '${EXTRA_VARS}'"
}

function getTargetsAsJsonArray()
{
    local result='{"targets": ['
    for target in $TARGETS
    do
        result="${result}\"${target}\","
    done
    result="${result::-1}]}"
    echo -e "${result}"
}

function getTargetsAsString()
{
    local result=
    for target in $TARGETS
    do
        result="${result}_${target}"
    done
    echo "${result:1}"
}

function getTargetSeedHosts()
{
    local result=
    local target=
    for target in $TARGETS
    do
        result="$result:$target-seed-hosts"
    done
    echo "${result:1}"
}

function getAbsFileName()
{
    echo "$(cd $(dirname ${1}); pwd)/$(basename ${1})"
}

function playbookDir()
{
    getAbsFileName "${SOURCE_PATH}/../ansible/playbooks"
}

function vaultFile()
{
    # This is now defaulted in the ansible playbooks to the same
    echo $(getAbsFileName "generated")/$(getDeploymentPhase)/mjdi.vault
}

function getInconnectFile()
{
    [[ -f "${INTERCONNETS}" ]] && { getAbsFileName ${INTERCONNETS}; return 0; }
    [[ -f "varfiles/${INTERCONNETS}.yml" ]] && { getAbsFileName varfiles/${INTERCONNETS}.yml; return 0; }
}

function getDeploymentPhase()
{
    egrep "^deployment_phase:[[:space:]]*'[A-Z0-9]*'" $(getInconnectFile) | awk -F "'" '{print $2}'
}

function executeCommand()
{
    local cmd="$1"
    local trap_clause=""
    local tag_clause=""
    [[ ! -z "${PASSWORD_FILE}" ]] && trap_clause="trap 'rm -f ${PASSWORD_FILE}' SIGINT ;"
    [[ ! -z "${TAGS}" ]] && tag_clause=" --tags ${TAGS}"

    log_info "Command: ${cmd}${tag_clause}"

    eval "echo \"${trap_clause}${cmd}${tag_clause}\" | /bin/bash"
}

function generateSecrets()
{
    local cmd="ansible-playbook $(playbookDir)/generate-secrets.yml \
      --extra-vars \"amq_vault_passphrase=${PASSPHRASE}\" \
      --extra-vars \"amq_interconnect_instances_file=$(getInconnectFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' $(extraArgsClause)"
    executeCommand "$cmd"
}

function generateCertificates()
{
    local cmd="ansible-playbook $(playbookDir)/setup-tls.yml \
      --extra-vars \"amq_interconnect_instances_file=$(getInconnectFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' $(extraArgsClause)"
    executeCommand "$cmd"
}

function deployAspera()
{
    local cmd="ansible-playbook $(playbookDir)/aspera.yml -i generated/$(getDeploymentPhase)/inventory \
      --extra-vars \"target_seed_hosts=$(getTargetSeedHosts)\" \
      --extra-vars \"amq_interconnect_instances_file=$(getInconnectFile)\" \
      --extra-vars '$(getTargetsAsJsonArray)' --vault-id psp@${PASSWORD_FILE} $(extraArgsClause)"
    executeCommand "$cmd"
}

function checkin()
{
    ${CHECKIN} || { log_warn "Suppressing any potential git commit/push"; return 0; }
    local cmd="ansible-playbook $(playbookDir)/git-checkin.yml -i generated/$(getDeploymentPhase)/inventory \
      --extra-vars \"target_seed_hosts=$(getTargetSeedHosts)\" \
      --extra-vars \"amq_interconnect_instances_file=$(getInconnectFile)\" $(extraArgsClause)"
    executeCommand "$cmd"
}

function createAsperaImages()
{
    local cmd="ansible-playbook $(playbookDir)/aspera-image.yml \
      --extra-vars \"amq_interconnect_instances_file=$(getInconnectFile)\" $(extraArgsClause) \
      --vault-id psp@${PASSWORD_FILE}"
    executeCommand "$cmd"
}

function executeScript()
{
    local cmd="ansible-playbook $(playbookDir)/main.yml -i generated/$(getDeploymentPhase)/inventory \
      --extra-vars \"target_seed_hosts=$(getTargetSeedHosts)\" \
      --extra-vars \"amq_interconnect_instances_file=$(getInconnectFile)\" \
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
        -t|--targets)
            setOption "${arg_key}" "TARGETS" "$(echo "${optarg}" | tr ',' ' ')"
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
      esac
      shift # past argument or value
    done

    [[ -z "${TARGETS}" ]] && { log_error "Require a comma separated list (-t)"; return 1; }

    [[ -z "${INTERCONNETS}" ]] && { log_error "Require an interconnect filename (-i)"; return 1; }

    [[ -z "${PASSPHRASE}" ]] && { log_error "Require an passphrase (-p)"; return 1; }

    PASSWORD_FILE=".p$$"
    echo "${PASSPHRASE}" > "${PASSWORD_FILE}"
    addTempFiles "${PASSWORD_FILE}"

    return 0
}


wrapper
