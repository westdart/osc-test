#!/usr/bin/env bash
########################################################################################################################
# General wrapper script
# The contract is thus:
# A top level script sources this file and provides the 'executeScript' function
# If additional options (parameters or switches) are to be used in the top level script:
#     ADDITONAL_ARGS_EXTRACT_SCRIPT : can be set to the function that extracts these options (default: extractArgs)
#     ADDITONAL_ARGS_PATTERN        : can be set to the pattern for all required arguments (or parameters)
#     ADDITONAL_SWITCHES_PATTERN    : can be set to the pattern for all required switches
# This wrapper also caters for:
# 1. Setting of log level and capturing the output to a log file
# 2. Execution of single functions within the script by utilising the '-f' option and supplying the functions name
#    followed by the required function arguments space separated.
# Also initialisation and finalisation can be modified by overriding the following variables which are pointers to
# functions:
#    INITIALISE_SCRIPT (default: wrapper_initialise)
#    FINALISE_SCRIPT   (default: wrapper_finalise)
########################################################################################################################
[[ -z ${CWD+x} || -z "$CWD" ]]                 && CWD=$(pwd)
[[ -z ${SCRIPT_PATH+x} || -z "$SCRIPT_PATH" ]] && SCRIPT_PATH=$(cd $(dirname "${BASH_SOURCE[0]}"); pwd)
[[ -z ${SOURCE_PATH+x} || -z "$SOURCE_PATH" ]] && SOURCE_PATH= ; ctx=$SCRIPT_PATH; anchor="wrapper.sh"; while [ -z "$SOURCE_PATH" ]; do [ -f "$ctx/$anchor" ] && { SOURCE_PATH=$ctx; break; }; [ "$ctx" == "/" ] && break; ctx=$(dirname $ctx); done; [ -z "$SOURCE_PATH" ] && { >&2 echo "Failed to locate dir!! Require a dir with the $anchor file and cannot find it."; exit 1; }; SOURCE_PATH=$(cd $SOURCE_PATH; pwd)

source "$SOURCE_PATH/logger.sh"
source "$SOURCE_PATH/common.sh"

ADDITONAL_ARGS_EXTRACT_SCRIPT=extractArgsextractArgs
INITIALISE_SCRIPT=wrapper_initialise
FINALISE_SCRIPT=wrapper_finalise

ONLY_SOURCE=false
GLOBAL=false # Variable directing whether the scripts are centrally (globally) organised - e.g. through nfs.
FAIL_ON_UNKNOWN_ARGS=false

shopt -s expand_aliases
shopt -s extglob

PID=$$
ARGS=$@
CONTEXT=
ENV=
FUNC=
DEV_NULL=/dev/null
LOCAL_MODE=false
PROMPT_ENABLED=0
EXEC_USER=
BACKGROUND_PROCESSES=
TEMP_FILES=
ON_ERROR_TEMP_FILES=

LOG_FILE_DIR='/tmp'

##############################################################################
# Description:
# Exit on error. This runs all clean up functions and logs the error
# Arg*: All args are echoed as an error
# Return: 1.
##############################################################################
function error_exit {
  usage
  onErrorCleanUp
  log_error "$*"
  if [[ $0 == *bash ]]
  then
    log_always "Running sourced with bash, not exiting shell"
  else
    exit 1
  fi
}
alias ERROR_EXIT='error_exit "Exit from ${0} at ${FUNCNAME} (@`echo $(( $LINENO - 1 ))`):"'

function usage()
{
  log_always "Generic usage: $0 [optional: -l <log-level> -f <function> <args>] (Note '-f <function> <args>' must be the last placed on the command line)"
}

function invoke()
{
  local func="$1"
  shift
  $func $@
}

function primeScript() {
  #set -i
  set -u
  trap "error_exit 'Received signal SIGHUP'" SIGHUP
  trap "error_exit 'Received signal SIGINT'" SIGINT
  trap "error_exit 'Received signal SIGTERM'" SIGTERM
}

function setOption() {
  local option="$1"
  shift
  local optionName="$1"
  if [[ $# -lt 2 || -z "$2" ]]
  then
      error_exit "'$option' requires a value."
  fi
  shift
  local optionValue="$@"
  printf -v $optionName "%s" "$optionValue"
}

function extractFunctionParameters() {
  while [ "$1" != "-f" ]
  do
      shift
  done
  shift

  log_trace "Function call: $*"
  func="$1"

  shift
  log_trace "Extracting function parameters: function = $func : paramters = $*"

  FUNCTION_PARAMETERS=$@
}

function wrapper_initialise()
{
  echo "" &> /dev/null
}

function wrapper_finalise()
{
  echo "" &> /dev/null
}

function addTempFiles()
{
  TEMP_FILES="$TEMP_FILES $@"
}

function addOnErrorTempFiles()
{
  ON_ERROR_TEMP_FILES="$ON_ERROR_TEMP_FILES $@"
}

##############################################################################
# Description:
# Remove temp files
# Return: 0.
##############################################################################
function removeTempFiles()
{
  local tempFiles=$@
  for file in $tempFiles
  do
    if [[ "$file" =~ ^\/[a-zA-Z0-9_-]*$ ]]
    then
      echo "ignoring root dir $file"
    else
      rm -rf $file
    fi
  done
}

##############################################################################
# Description:
# Clean up temporary resources
# Return: 0.
##############################################################################
function cleanUp()
{
  killTempProcesses

  removeTempFiles $TEMP_FILES
}

##############################################################################
# Description:
# Clean up temporary resources
# Return: 0.
##############################################################################
function onErrorCleanUp()
{
  removeTempFiles $ON_ERROR_TEMP_FILES

  cleanUp
}

function killTempProcesses()
{
  sleep 2 # give the processes some time to catch up
  #kill any child processes started in background
  for pid in $BACKGROUND_PROCESSES
  do
    log_debug "Killing $pid: $BACKGROUND_PROCESSES"
    (kill $pid) > $DEV_NULL 2>&1
  done
  BACKGROUND_PROCESSES=
}

##############################################################################
# Description:
# Make sure only root can run script
# Return: 0 if running as root, otherwise 1.
##############################################################################
function runningAsRoot()
{
	runningAsUser "root"
}

function runningAsUser()
{
	if [ `whoami` = "$1" ]; then
    return 0
	fi
	return 1
}

function runAs() {
  local user="$1"
  local script="$2"

  su "$user" <<'EOF'
"$script"
EOF
}

function commonRead()
{
  if [ "$PROMPT_ENABLED" == "0" ]
  then
    read $*
    return 0
  fi
  return 1
}

function getInput()
{
  local input=
  local result=0
  while [ -z "$input" ]
  do
    commonRead $@ input
    if [ "$?" == "1" ]
    then
        #unable to prompt
        return 1
    fi
  done
  echo "$input"
}

function getSecretInput()
{
  getInput "-s"
}

function yesOrNo()
{
  local answer=
  local result=0
  while [[ "$answer" != "y" && "$answer" != "n" ]]
  do
    commonRead answer
    if [ "$?" == "1" ]
    then
        #unable to prompt
        return 1
    fi
  done
  echo "$answer"
}

function confirmed()
{
    local ans=
    local result=0
    ans=$(yesOrNo)
    [ "$ans" == 'n' ] && result=1
    return $result
}

function enablePrompt()
{
  PROMPT_ENABLED=0
}

function disablePrompt()
{
  PROMPT_ENABLED=1
}

function extractArgs()
{
    echo "" > /dev/null
}

function wrapper()
{
  LOG_ENTRY
  local result=0

  [[ ! -z "$EXEC_USER" ]] && { ! runningAsUser $EXEC_USER && { log_error "Not running as user: $EXEC_USER"; return 1; } }

  [ ! -d $LOG_FILE_DIR ] && { mkdir -p "$LOG_FILE_DIR" || { log_error "failed to create log dir '$LOG_FILE_DIR'"; return 1; } }
  LOG_FILE="$LOG_FILE_DIR/$(basename $0)-$(date +%Y-%m-%d_%H_%M_%S).log"
  exec >  >(tee -a ${LOG_FILE})
  exec 2> >(tee -a ${LOG_FILE} >&2)

  if $ONLY_SOURCE
  then
    log_info "Only sourcing scripts, exiting."
    return 0
  fi

  if [ $result == 0 ]
  then
    if isFunction $ADDITONAL_ARGS_EXTRACT_SCRIPT
    then
      $ADDITONAL_ARGS_EXTRACT_SCRIPT $ARGS
      if [ $? != 0 ]
      then
        [ -z "$FUNC" ] && error_exit "Failed to extract required arguments, exiting"
        log_warn "Failed to extract required arguments, continuing as under single function execution."
      fi
    fi

    if [ ! -z "$INITIALISE_SCRIPT" ]
    then
      $INITIALISE_SCRIPT
      if [ $? != 0 ]
      then
          log_error "Failed to initialise script execution, exiting"
          result=254
      fi
    fi

    if [ $result == 0 ]
    then
      if [ -z "$FUNC" ]
      then
        executeScript
        result=$?
      else
        log_debug "FUNCTION=$FUNC"

        #Now capture any 'function' parameters:
        extractFunctionParameters $ARGS

        log_always "Function execution : $0->$FUNC $FUNCTION_PARAMETERS"

        ${FUNC} $FUNCTION_PARAMETERS
        result=$?

        log_always "Completed function : $0->$FUNC $FUNCTION_PARAMETERS ($result)"
      fi

      if [ ! -z "$FINALISE_SCRIPT" ]
      then
         $FINALISE_SCRIPT $result
        if [ $? != 0 ]
        then
          log_error "Failed to finalise script execution, exiting"
          result=255
        fi
      fi
    fi
  fi

  if [ $result == 0 ]
  then
    cleanUp "y"
  else
    onErrorCleanUp "y"
  fi

  LOG_EXIT
  return $result
}


if [[ -z ${ADDITONAL_ARGS_PATTERN+x} || -z "$ADDITONAL_ARGS_PATTERN" ]]
then
  ADDITONAL_ARGS_PATTERN=
fi

if [[ -z ${ADDITONAL_SWITCHES_PATTERN+x} || -z "$ADDITONAL_SWITCHES_PATTERN" ]]
then
  ADDITONAL_SWITCHES_PATTERN=
fi

# Process arguments
while [[ $# > 0 ]]
do
  ARG_KEY="$1"
  OPTARG=
  if [ $# -gt 1 ]
  then
    OPTARG="$2"
  fi

  case $ARG_KEY in
    -f|--function)
        setOption "$ARG_KEY" "FUNC" "$OPTARG"
        shift # past argument
        ;;
    -l|--log-level)
        LOG_LEVEL_ARG="$OPTARG"
        setLogLevelByString "$OPTARG"
        shift # past argument
        ;;
    --source)
        ONLY_SOURCE=true
        ;;
    --no-prompt)
        disablePrompt
        ;;
    $ADDITONAL_ARGS_PATTERN)
        shift # past argument
        ;;
    $ADDITONAL_SWITCHES_PATTERN)
        ;;
    -*)
        if $FAIL_ON_UNKNOWN_ARGS
        then
            error_exit "Invalid option: $ARG_KEY"
        fi
        shift # past argument
        ;;
  esac
  shift # past argument or value
done

[[ $ONLY_SOURCE ]] || primeScript
