#!/bin/bash
##############################################################################
# Header:
# Logger functions. 'Level' based logging for bash scripts.
##############################################################################

# const
LOG_MAX=9
LOG_TRACE=6
LOG_DEBUG=5
LOG_INFO=3
LOG_WARN=2
LOG_ERROR=1
LOG_ALWAYS=0
NO_LOG=1
LOG_LEVEL=${LOG_INFO}

LOGGER_LOG_FILE=

LOG_ENABLE_CONSOLE="true"

LOG_LINE_FEED_REQUIRED=false

alias LOG_ENTRY='log_debug "Entering $FUNCNAME"'
alias LOG_EXIT='log_debug "Exiting $FUNCNAME"'

CWD=`pwd`

LOGGER_CLR_RED='\033[1;31m'
LOGGER_CLR_GREEN='\033[1;32m'
LOGGER_CLR_NC='\033[0m' # No Color

TEST_COUNT=0
FAIL_COUNT=0
PASS_COUNT=0

function scriptDir() {
    if [[ "$0" == "-bash" || "$0" == "-sh" ]]
    then
        echo "$CWD"
    else
        dirname "$0"
    fi
}

function scriptName() {
    if [[ "$0" == "-bash" || "$0" == "-sh" ]]
    then
        echo "-bash"
    else
        basename "$0"
    fi
}

function escapestar() {
        echo "$@" | sed 's:\*:\\\*:g'
}

##############################################################################
# Description:
# Set the log level
# arg1: The log level
# arg2: The level at which to log it
# Return: 0.
##############################################################################
setLogLevel(){
	if [ ! -z "${1}" ]
    then
        LOG_LEVEL="$1"
	fi
}

setLogLevelByString(){
	if [ ! -z "${1}" ]
    then
        getLogLevelByString "${1}"
        LOG_LEVEL="$?"
	fi
}

getLogLevelByString(){
    if [ "${1}" == "TRACE" ]
    then
        return $LOG_TRACE
    elif [ "${1}" == "DEBUG" ]
    then
        return $LOG_DEBUG
    elif [ "${1}" == "INFO" ]
    then
        return $LOG_INFO
    elif [ "${1}" == "WARN" ]
    then
        return $LOG_WARN
    elif [ "${1}" == "ERROR" ]
    then
        return $LOG_ERROR
    elif [ "${1}" == "ALWAYS" ]
    then
        return $LOG_ALWAYS
    fi
    return $LOG_INFO
}

logLevelEnabled(){
    getLogLevelByString $1
    if [ $? -le ${LOG_LEVEL} ];then
        return 0
    fi
    return 1
}

X_getStream(){
    if [ $# -gt 0 ]
    then
        if [[ $1 == "stdout" || $1 == "stderr" ]]
        then
            echo "$1"
            return 0
        fi
    fi
    return 1
}

X_getPreamble() {
    local level=$1
    local padding=$[2+$[5-${#level}]]
    local preamble=$(printf "[%s]%-"$padding"s" "$level")
    echo "$preamble"
}

X_getFormatStart() {
    local level=$1
    [[ "${level}" == "FAILED" ]] && echo "${LOGGER_CLR_RED}"
    [[ "${level}" == "PASSED" ]] && echo "${LOGGER_CLR_GREEN}"
}

X_getFormatEnd() {
    local level=$1
    [[ "${level}" == "FAILED" ]] && echo "${LOGGER_CLR_NC}"
    [[ "${level}" == "PASSED" ]] && echo "${LOGGER_CLR_NC}"
}

X_log() {
    local level=$1
    shift
    local stream=
    stream=$(X_getStream $@)
    if [ $? == 0 ];then
        shift
    fi

    println $stream "$(X_getFormatStart $level)$(X_getPreamble $level)$@$(X_getFormatEnd $level)"
}

##############################################################################
# Description:
# Log a message to standard out. Checks the level is in force before logging
# arg1: The message to log
# arg2: The level at which to log it
# Return: 0.
##############################################################################
log(){
	MESSAGE=$1
	LEVEL=$2

	# default level if not passed
	if [ "${LEVEL}" == "" ];then
	LEVEL=${LOG_ALWAYS}
	fi

    # call the appropriate function
    case "${LEVEL}" in
        ${LOG_TRACE})
           log_trace ${MESSAGE}
        ;;
        ${LOG_DEBUG})
           log_debug ${MESSAGE}
        ;;
        ${LOG_INFO})
           log_info ${MESSAGE}
        ;;
        ${LOG_WARN})
           log_warn ${MESSAGE}
        ;;
        ${LOG_ERROR})
           log_error ${MESSAGE}
        ;;
        *)
           log_always ${MESSAGE}
        ;;
    esac
}

log_disableConsole() {
    LOG_ENABLE_CONSOLE="false"
}

log_enableConsole() {
    LOG_ENABLE_CONSOLE="true"
}

##############################################################################
# Description:
# Log a debug message to standard out.
# arg1: The message to log
# Return: 0.
##############################################################################
log_debug(){
    if [ ${LOG_DEBUG} -le ${LOG_LEVEL} ];then
	   X_log "DEBUG" "${@}"
    fi
}

##############################################################################
# Description:
# Log a trace message to standard out.
# arg1: The message to log
# Return: 0.
##############################################################################
log_trace(){
    if [ ${LOG_TRACE} -le ${LOG_LEVEL} ];then
	   X_log "TRACE" "${@}"
    fi
}

##############################################################################
# Description:
# Log an info message to standard out.
# arg1: The message to log
# Return: 0.
##############################################################################
log_info(){
    if [ ${LOG_INFO} -le ${LOG_LEVEL} ];then
	   X_log "INFO" "${@}"
    fi
}

##############################################################################
# Description:
# Log progress type line, i.e. leave cursor to overwrite next time
# arg1: The message to log
# Return: 0.
##############################################################################
log_progress(){
    if [ ${LOG_INFO} -le ${LOG_LEVEL} ];then
        println "$(X_getPreamble 'INFO')${1}\r"
    fi
}

##############################################################################
# Description:
# Log an info message to standard out.
# arg1: The file to log
# Return: 0.
##############################################################################
log_info_file(){
    if [ ${LOG_INFO} -le ${LOG_LEVEL} ];then
        log_file "info" "${1}"
    fi
}
##############################################################################
# Description:
# Log an debug message to standard out.
# arg1: The file to log
# Return: 0.
##############################################################################
log_debug_file(){
    if [ ${LOG_DEBUG} -le ${LOG_LEVEL} ];then
        log_file "debug" "${1}"
    fi
}

##############################################################################
# Description:
# Log message to standard out at required level.
# arg1: The file to log
# arg2: The level at which to log as a name (e.g. 'info' or 'debug' - case sensitive)
# Return: 0.
##############################################################################
log_file(){
    printFile "${2}" "${1}"
}

##############################################################################
# Description:
# Log a warning message to standard out.
# arg1: The message to log
# Return: 0.
##############################################################################
log_warn(){
    if [ ${LOG_WARN} -le ${LOG_LEVEL} ];then
        X_log "WARN" "${@}"
    fi
}

##############################################################################
# Description:
# Log an error message to standard out.
# arg1: The message to log
# Return: 0.
##############################################################################
log_error(){
    if [ ${LOG_ERROR} -le ${LOG_LEVEL} ];then
        X_log "ERROR" "${@}"
    fi
}

##############################################################################
# Description:
# Log an fail message to standard out.
# arg1: The message to log
# Return: 0.
##############################################################################
log_test(){
    if [ ${LOG_ERROR} -le ${LOG_LEVEL} ];then
        TEST_COUNT=$[$TEST_COUNT+1]
        X_log "TEST" "${@}"
    fi
}

##############################################################################
# Description:
# Log an fail message to standard out.
# arg1: The message to log
# Return: 0.
##############################################################################
log_fail(){
    if [ ${LOG_ERROR} -le ${LOG_LEVEL} ];then
        FAIL_COUNT=$[$FAIL_COUNT+1]
        X_log "FAILED" "${@}"
    fi
}

##############################################################################
# Description:
# Log an passed message to standard out.
# arg1: The message to log
# Return: 0.
##############################################################################
log_pass(){
    if [ ${LOG_ERROR} -le ${LOG_LEVEL} ];then
        PASS_COUNT=$[$PASS_COUNT+1]
        X_log "PASSED" "${@}"
    fi
}

##############################################################################
# Description:
# Log a message irrespective of level to standard out.
# arg1: The message to log
# Return: 0.
##############################################################################
log_always(){
    local level=${LOG_ALWAYS}
    if [ ${level} -le ${LOG_LEVEL} ];then
        X_log "-" "${@}"
    fi
}

##############################################################################
# Description:
# Log a message irrespective of level to standard out and do not put in a preamble.
# arg1: The message to log
# Return: 0.
##############################################################################
log_raw(){
    local level=${LOG_ALWAYS}
    if [ ${level} -le ${LOG_LEVEL} ];then
        X_log "-" "${@}"
    fi
}

##############################################################################
# Description:
# Log a message at a custom level to standard out.
# arg1: The level at which to log it
# arg2: The message to log
# Return: 0.
##############################################################################
log_all() {
    local level=$1
    if [ ${level} -le ${LOG_LEVEL} ];then
        shift
        X_log "$level" "${@}"
    fi
}

setLogFile() {
    if [ -z "${LOGGER_LOG_FILE}" ]
    then
        LOGGER_LOG_FILE="${1}"
        if [ ! -e "${LOGGER_LOG_FILE}" ]
        then
            touch "${LOGGER_LOG_FILE}"
        fi
        log_always "Log output going to ${LOGGER_LOG_FILE}"
    fi
}

logFileSet() {
    if [ -z "${LOGGER_LOG_FILE}" ]
    then
        return 1
    else
        return 0
    fi
}

printLogln() {
    if [ ! -z "${LOGGER_LOG_FILE}" ]
    then
        echo -e "${1}" >> "${LOGGER_LOG_FILE}"
    fi
}

######################################################################################
# Print a line to the output stream and/or file
# Posiion based parameters:
# <stream>  : 'stdout' - to redirect to stdout (default is stderr)
# <message> : All subsequent arguments are concatonated into a single message
######################################################################################
println() {
    local func=echoStdErr

    if [ $# -gt 1 ]
    then
        if [ "$1" == "stdout" ]; then
            func=echoStdOut
            shift
        elif [ "$1" == "stderr" ]; then
            func=echoStdErr
            shift
        fi
    fi

    local message="[`date -u +%H:%M:%S`] [`hostname`] [$(scriptName)] ${@}"
    if [[ "$NO_LOG" == "1" && "$LOG_ENABLE_CONSOLE" == "true" ]]; then
        ${func} "$message"
    fi

    if [ "$NO_LOG" == "1" ]; then
        printLogln "$message"
    fi
}

echoStdOut() {
    local option=
    local params="$@"
    local length=$((${#params}-2))
    [ "${params:$length:2}" == "\r" ] && { option="-n"; LOG_LINE_FEED_REQUIRED=true; }
    if $LOG_LINE_FEED_REQUIRED && [[ "${params:$length:2}" != "\r" ]]; then
        echo "" 1>&1
        LOG_LINE_FEED_REQUIRED=false
    fi
    echo -e $option "$params" 1>&1;
}

echoStdErr() {
    local option=
    local params="$@"
    local length=$((${#params}-2))
    [ "${params:$length:2}" == "\r" ] && { option="-n"; LOG_LINE_FEED_REQUIRED=true; }
    if $LOG_LINE_FEED_REQUIRED && [[ "${params:$length:2}" != "\r" ]]; then
        echo "" 1>&2
        LOG_LINE_FEED_REQUIRED=false
    fi
#    echo -e $option "$params" 1>&2;
    printf "${params}\n" 1>&2;
}

printFile() {
    if [ -e "${1}" ]; then
        IFS_=$IFS
        IFS=$'\n'
        while read line;
        do
            log_$2 "$line"
        done < "${1}"
        IFS=$IFS_
    fi
}