#!/bin/bash
########################################################################################################################
# Common functions
# Dependencies : logger.sh
########################################################################################################################
SHOPT_ORIG="$(printf %s\\n "$-")"

USERNAME=$(echo $USER | sed 's/_/./g')
PROMPT_ENABLED=0
DEV_NULL=/dev/null

if ! which dzdo &> ${DEV_NULL}
then
    ELEVATE_AND_EXECUTE=sudo
else
    ELEVATE_AND_EXECUTE=dzdo
fi

function getCurrentTimeInMillis()
{
    echo $(($(date +%s%N)/1000000))
}

function getDate() {
    echo $(date -u +%Y%m%d-%H%M%S)
}

function getDateAndZone() {
    echo $(date -u +%Y%m%d-%H%M%S%Z)
}

########################################################################################################################
# From a starting position search for the location of an anchor file, iteratively moving up the directory tree until the
# first is found. If more than one is found, the latest is picked.
########################################################################################################################
function reverseSearch()
{
    local anchor="$1"
    local startPath="$2"
    local ctx=$startPath
    local destPath=

    while [ -z "$destPath" ]
    do
        if [ ! -z "$(find $ctx -type f -name $anchor)" ]
        then
            destPath=$(dirname $(ls -lart $(find $ctx -type f -name $anchor) | tail -n1 | awk '{print $NF}'))
            break
        fi
        if [[ "$ctx" == "." || "$ctx" == "/" ]]
        then
            break
        fi
        ctx=$(dirname $ctx)
    done
    [ -z "$destPath" ] && { log_error "Failed to locate dir!! Require a dir with the $anchor script and cannot find it."; return 1; }
    destPath=$(cd $destPath; pwd)
    echo $destPath
    return 0
}

########################################################################################################################
# findDir
# Execute a search up the directory tree until the directory is found
########################################################################################################################
function reverseFindDir()
{
    local dir="$1"
    local startPath="$2"
    local destPath=
    local ctx=$startPath
    local hidden=

    startsWith "$dir" "." && hidden="."

    while [ -z "$destPath" ]
    do
        log_debug "ctx=$ctx"
        ls -ld ${ctx}/${hidden}*/ | awk '{print $NF}' | awk -F "/" '{print $(NF-1)}' | grep -q "^${dir}$"
        if [ $? == 0 ]
        then
            destPath="$(cd $ctx; pwd)/$dir"
        fi
        if [ "$(cd $ctx; pwd)" == "/" ]
        then
            break
        fi
        ctx="${ctx}/.."
    done
    [ -z "$destPath" ] && { log_error "Failed to locate dir ($dir) from $startPath"; return 1; }
    echo $destPath
    return 0
}

########################################################################################################################
# findFile
# Execute a search up the directory tree until the file is found
########################################################################################################################
function reverseFindFile()
{
    local file="$1"
    local startPath="$2"
    local destPath=
    local ctx=$startPath

    while [ -z "$destPath" ]
    do
        log_debug "ctx=$ctx"
        ls -l ${ctx}/$file 2>${DEV_NULL} | awk '{print $NF}' | grep -q "^${file}$"
        if [ $? == 0 ]
        then
            destPath="$(cd $(ctx)/$(dirname $file); pwd)/$(basename $file)"
        fi
        if [ "$(cd $ctx; pwd)" == "/" ]
        then
            break
        fi
        ctx="${ctx}/.."
    done
    [ -z "$destPath" ] && { log_error "Failed to locate file ($file) from $startPath"; return 1; }
    echo $destPath
    return 0
}

########################################################################################################################
# Test if a shell option is set 'on'
########################################################################################################################
function shoptOn()
{
    local letter="${1:0:1}"
    printf %s\\n "$-" | grep "$letter" &>${DEV_NULL}
}

########################################################################################################################
# Test if a shell option is set 'off'
########################################################################################################################
function shoptOff()
{
    shoptOn "$1"
    [ $? != 0 ] && return 0
    return 1
}

########################################################################################################################
# Set a shell option to 'on'
########################################################################################################################
function setShoptOn()
{
    local letter="${1:0:1}"
    set -${letter}
}

########################################################################################################################
# Set a shell option to 'off'
########################################################################################################################
function setShoptOff()
{
    local letter="${1:0:1}"
    set +${letter}
}

########################################################################################################################
# Reset all shell options to their original values or only reset the option passed in as a parameter
# Arg1 : (Optional) The option to revert to its original state
########################################################################################################################
function resetShopt()
{
    if [ $# -eq 0 ]
    then
        set -${SHOPT_ORIG}
    else
        local letter="${1:0:1}"
        if [[ "$SHOPT_ORIG" =~ "$letter" ]]
        then
            setShoptOn $letter
        else
            setShoptOff $letter
        fi
    fi
}

########################################################################################################################
# Trim a string of leading and trailing whitspace
# Arg1 : The string to trim
########################################################################################################################
function trim() {
    local var=$1
    var="${var#"${var%%[![:space:]]*}"}"   # remove leading whitespace characters
    var="${var%"${var##*[![:space:]]}"}"   # remove trailing whitespace characters
    echo -n "$var"
}

########################################################################################################################
# Test if 'str1' starts with 'str2'
########################################################################################################################
function startsWith() {
    local str1="$1"
    local str2="$2"
    subdStr=${str1:0:${#str2}}
    if [ "$subdStr" == "$str2" ]
    then
        return 0
    fi
    return 1
}

########################################################################################################################
# Test if 'str1' ends with 'str2'
########################################################################################################################
function endsIn() {
    local str1="$1"
    local str2="$2"
    echo "$str1" | grep -q "${str2}\$"
}

########################################################################################################################
# Convert all parameters passed to lower case
########################################################################################################################
function toLower()
{
    echo "$@" | tr '[:upper:]' '[:lower:]'
}

########################################################################################################################
# Convert all parameters passed to upper case
########################################################################################################################
function toUpper()
{
    echo "$@" | tr '[:lower:]' '[:upper:]'
}

########################################################################################################################
# This function escapes each curly brace from all parameters passed for use in regular expressions.
# Arg1: The string to escape
# Return: 0 if processed successfully, and echo the result
########################################################################################################################
function escapeCurlyBraces() {
    echo "$@" | sed 's:{:\\{:g' | sed 's:}:\\}:g'
}

########################################################################################################################
# This function escapes each square brace from all parameters passed for use in regular expressions.
# Return: 0 if processed successfully, and echo the result
########################################################################################################################
function escapeSquareBraces() {
    echo "$@" | sed 's:\[:\\\[:g' | sed 's:\]:\\\]:g'
}

########################################################################################################################
# This function escapes slash ('/') characters from all parameters passed for use in regular expressions.
# Return: 0 if processed successfully, and echo the result
########################################################################################################################
function escapeSlash() {
    echo "$@" | sed 's:\/:\\/:g'
}

########################################################################################################################
# This function escapes double quote ('"') characters from all parameters passed for use in regular expressions.
# Return: 0 if processed successfully, and echo the result
########################################################################################################################
function escapeDoubleQuotes() {
    echo "$@" | sed 's:":\\":g'
}

########################################################################################################################
# This function un-escapes double quote ('"') characters from all parameters passed.
# Return: 0 if processed successfully, and echo the result
########################################################################################################################
function unescapeDoubleQuotes() {
    echo "$@" | sed 's:\\":":g'
}

########################################################################################################################
# This function escapes single quote ("'") characters from all parameters passed for use in regular expressions.
# Return: 0 if processed successfully, and echo the result
########################################################################################################################
function escapeSingleQuotes() {
    echo "$@" | sed "s:':\\\':g"
}

########################################################################################################################
# This function un-escapes single quote ("'") characters from all parameters passed.
# Return: 0 if processed successfully, and echo the result
########################################################################################################################
function unescapeSingleQuotes() {
    echo "$@" | sed "s:\\\':':g"
}

########################################################################################################################
# This function escapes ampersand ('&') characters from all parameters passed for use in regular expressions.
# Return: 0 if processed successfully, and echo the result
########################################################################################################################
function escapeAmpersand() {
        echo "$@" | sed 's:&:\\&:g'
}

########################################################################################################################
# This function escapes dot ('.') characters from all parameters passed for use in regular expressions.
# Return: 0 if processed successfully, and echo the result
########################################################################################################################
function escapeDot() {
    echo "$@" | sed 's:\.:\\\.:g'
}

########################################################################################################################
# This function escapes star ('*') characters from all parameters passed for use in regular expressions.
# Return: 0 if processed successfully, and echo the result
########################################################################################################################
function escapestar() {
    echo "$@" | sed 's:\*:\\\*:g'
}

########################################################################################################################
# This function escapes hash ('#') characters from all parameters passed for use in regular expressions.
# Return: 0 if processed successfully, and echo the result
########################################################################################################################
function escapehash() {
    echo "$@" | sed 's:\#:\\\#:g'
}

########################################################################################################################
# This function escapes hash ('$') characters from all parameters passed for use in regular expressions.
# Return: 0 if processed successfully, and echo the result
########################################################################################################################
function escapeDollar() {
    echo "$@" | sed 's:\$:\\\$:g'
}

########################################################################################################################
# This function escapes all regular expression sensitive characters from all parameters passed
# Return: 0 if processed successfully, and echo the result
########################################################################################################################
function escapeRegex() {
    echo $(escapeSquareBraces $(escapeCurlyBraces $(escapeSlash $(escapeDot $(escapestar "$@")))))
}

########################################################################################################################
# URL encode the string passed
# Arg1 : The string to encode
# Return : 0 and echo the result
########################################################################################################################
function urlencode() {
  local string="${1}"
  local strlen=${#string}
  local encoded=""
  local pos c o

  for (( pos=0 ; pos<strlen ; pos++ )); do
     c=${string:$pos:1}
     echo "$c"
     case "$c" in
        [-_.~a-zA-Z0-9] ) o="${c}" ;;
        * )               printf -v o '%%%02x' "'$c"
     esac
     encoded+="${o}"
  done
  echo "${encoded}"
}

########################################################################################################################
# Replace a Json key/value pair with a new value. The value is replaced in the existing file
# Arg1 : The key
# Arg2 : The new value
# Arg3 : The file
# Return : 0 if value was replaced, otherwise 1
########################################################################################################################
function replaceOldJsonValue()
{
    local key="$1"
    local newValue="$2"
    local file="$3"

    log_debug "replaceOldJsonValue: newValue = $newValue"

    local searchString="\"$key\":\s*\".*\""
    local replaceString="\"$key\":\t\"$newValue\""

    local val_to_replace=$(escapehash $replaceString)

    log_debug "replaceOldJsonValue: searchString = $searchString"
    log_debug "replaceOldJsonValue: replaceString = $replaceString"

    sed -i "s#${searchString}#${val_to_replace}#g" $file
    if [ $? != 0 ]
    then
        log_error "was unable to replace the password: search string '$searchString' with '$replaceString' (escaped: $val_to_replace)"
        return 1
    fi
    return 0
}

########################################################################################################################
# Ensure text in a file
# Arg1 : The search string
# Arg2 : The new value
# Arg3 : The file
# Return : 0 on success, otherwise 1
########################################################################################################################
function ensureInFile()
{
    local searchStr="$1"
    local newValue="$2"
    local file="$3"
    local result=

    if [ ! -e "$file" ]
    then
        echo "${newValue}" > $file || { log_error "Failed to create $file"; return 1; }
        return 0
    fi

    replaceInFile "$searchStr" "$newValue" "$file"
    result=$?

    if [ $result == 3 ]
    then
        echo "${newValue}" >> $file || { log_error "Failed to append to $file"; return 1; }
    else
        [ $result != 0 ] && return 1
    fi
    return 0
}


########################################################################################################################
# Replace text in a file
# Arg1 : The search string
# Arg2 : The new value
# Arg3 : The file
# Return : 0 if value was replaced, otherwise 1, if there was an error, 2 if the string already exists and 3 if the
#          search string was not found
########################################################################################################################
function replaceInFile()
{
    local searchStr="$1"
    local newValue="$2"
    local file="$3"

    log_debug "replaceInFile: '$searchStr' => '$newValue' in $file"

    local sed_newValue=$(escapehash $newValue)

    local replaceStrMatch=$(escapeRegex $newValue)
    egrep -q "$replaceStrMatch" "$file" &> ${DEV_NULL}             && { log_debug "replaceInFile: Replacement already exists in $file: '$newValue' (escaped: '$replaceStrMatch')"; return 2; }
    egrep -q "$searchStr" "$file" &> ${DEV_NULL}                   || { log_debug "replaceInFile: Search string not found, nothing to replace in $file: $searchStr"; return 3; }
    sed -i "s#${searchStr}#${sed_newValue}#g" $file &> ${DEV_NULL} || { log_error "was unable to effect replacement in $file: search string '$searchStr' with '$newValue' (escaped: $sed_newValue)"; return 1; }
    return 0
}

function isFunction()
{
    local func=$1
    type $func 2> ${DEV_NULL} | grep "$func is a function" &> ${DEV_NULL}
}

function isInteger()
{
    re="^[0-9]+$"
    [[ "$1" =~ $re ]] && return 0
    return 1
}

function echo_server_ping()
{
    local servers="$1"
    local threshold=0
    [ $# -gt 1 ] && threshold=$2


    local server=
    for server in $servers
    do
        local time=$(ping -q -c 1 $server | grep rtt | awk '{print $4}' | awk -F'/' '{print $1}')
        result=$(echo "$time>=$threshold" | bc -l)
        [ $result == 1 ] && echo -e "$server\t$time\t($(date -u))"
    done
}

function echo_iowait()
{
    local threshold=0
    [ $# -gt 0 ] && threshold=$1

    local iowait_measure=$(iostat | grep -A1 iowait | tail -n1 | awk '{print $4}')
    result=$(echo "$iowait_measure>=$threshold" | bc -l)
    [ $result == 1 ] && echo -e "$iowait_measure\t($(date -u))"
}

function echo_swap()
{
    local threshold=0
    [ $# -gt 0 ] && threshold=$1

    local swap_size=$(swapon --summary | grep partition | tail -n1 | awk '{print $4}')
    result=$(echo "$swap_size>=$threshold" | bc -l)
    [ $result == 1 ] && echo -e "$swap_size\t($(date -u))"
}

function X_sftp()
{
    local function=$1
    local server=$2
    local user=$USERNAME
    local dir=
    local filespec=

    if [ $# -gt 3 ]
    then
        dir="$3"
        filespec="$4"
    else
        dir="$USERNAME"
        filespec="$3"
    fi

    log_info "Executing sftp $function on '$server:$dir' with filespec '$filespec' as user '$user'"

    if [ "$function" == "mput" ]
    then
        local sftpOptions=
        type -t getSftpServerOptions &> ${DEV_NULL} && sftpOptions=$(getSftpServerOptions $server)
        sftp $sftpOptions $user@$server 2> ${DEV_NULL} <<EOF
mkdir $dir
cd $dir
$function $filespec
EOF
    else
        sftp $user@$server 2> ${DEV_NULL} <<EOF
cd $dir
$function $filespec
EOF
    fi

    if [ $? != 0 ]
    then
        log_error "Failed to execute $function on $server:/$dirs with $filespec as $user."
        return 1
    else
        log_info "Completed executing sftp $function on '$server:$dir' with filespec '$filespec' as user '$user'"
        return 0
    fi
}

function sftpPut()
{
    X_sftp "mput" $@ || { log_error "Failed to upload file to sftp. Check the file exists and that you have write permissions on the sftp folder"; return 1; }
    return 0
}

function sftpGet()
{
    X_sftp "mget" $@ || { log_error "Failed to get file from sftp. Check the file exists and that you have write permissions on $(pwd)"; return 1; }
    return 0
}

function getInput() {
    log_always "$@:"
    local text=""
    commonRead text
    [ "$?" == "1" ] && { log_error "'no-prompt' is enabled but do not have all the passwords! Exiting getPassword"; return 1; }

    while [ -z "${text}" ]
    do
        log_always "$@:"
        commonRead text
    done

    echo "$text"
}

function getPassword() {
    log_always "$@:"
    local password=""
    commonRead -s password
    [ "$?" == "1" ] && { log_error "'no-prompt' is enabled but do not have all the passwords! Exiting getPassword"; return 1; }

    while [ -z "${password}" ]
    do
        log_always "$@:"
        commonRead -s password
    done

    echo "$password"
}

function getConfirmedPassword() {
    local password=
    local confirmedPassword=
    local retries=0
    password=$(getPassword $@)

    while [ "$confirmedPassword" != "$password" ]; do
        confirmedPassword=$(getPassword "Confirm")
        retries=$[$retries+1]
        [ $retries -gt 3 ] && { log_error "Failed to confirm password."; return 1; }
    done
    echo $password
}

function commonRead() {
    if [ "$PROMPT_ENABLED" == "0" ]
    then
        read $*
        return 0
    fi
    return 1
}

function enablePrompt() {
    PROMPT_ENABLED=0
}

function disablePrompt() {
    PROMPT_ENABLED=1
}

function promptEnabled() {
    return $PROMPT_ENABLED
}


##############################################################################
# Description:
# replace the search string with the replacement in the file.
# This escapes both the search string as well as the replace string
# Arg1: The string to search for.
# Arg1: The replacement
# Arg3: the file
# Arg4: (optional) Backup Filename. If specified only a single backup is made. If the file exists then no change is
#       recorded
# Return 0 if replacement successful, 1 if there was an error, 2 if no string was there to replace and 3 if what was
#        being replaced was already there
##############################################################################
function replaceInFile()
{
    local searchStr="$1"
    local replaceStr="$2"
    local fileName="$3"
    local backupFileName=
    if [ $# -gt 3 ]
    then
        backupFileName="$4"
    fi

    local result=1

    local tmpVersion="${fileName}.tmp"
    addTempFiles "$tmpVersion"

    log_trace "replaceInFile: Replacing '$searchStr' with '$replaceStr' in  $fileName"
    local searchText=$(escapeSlash "$searchStr")
    local searchTextResult="$?"
    local replacementText=$(escapeSlash "$replaceStr")
    local replacementTextResult="$?"

    if [[ "$searchTextResult" == "0" && "$replacementTextResult" == "0" ]]
    then
        egrep -q "$replaceStr" "$fileName" > $DEV_NULL 2>&1
        if [ "$?" == "0" ]
        then
            result=3
        else
            egrep -q "$searchStr" "$fileName" > $DEV_NULL 2>&1
            if [ "$?" != "0" ]
            then
                result=2
            else
                local sedSearchStr=$(escapeCurlyBraces "$searchText")
                #TODO - why is there a escaping of the search str for curly braces - this can only be for nested addresses or multiple commands - not sure where that use case is!
                #TODO   added a separate call using non escaped value if the escaped version fails - but this is not a good solution as ther should be certainty on what gets replaced.
                log_debug "replaceInFile: Searching Text: '$sedSearchStr' and replacing with '$replacementText' in  $fileName"
                cat "${fileName}" | sed 's/'"$sedSearchStr"'/'"$replacementText"'/g' > "$tmpVersion" 2>$DEV_NULL
                local result="$?"
                if [ "$result" != "0" ]
                then
                    cat "${fileName}" | sed 's/'"$searchText"'/'"$replacementText"'/g' > "$tmpVersion" 2>$DEV_NULL
                    result="$?"
                fi

                if [ "$result" == "0" ]
                then
                    if [[ ! -z "$backupFileName" &&  ! -e "$backupFileName" ]]
                    then
                        cp "$fileName" "$backupFileName"
                    fi
                    local permissions=$(stat -c%a "$fileName")
                    chmod $permissions "$tmpVersion"
                    if [ "$?" == "0" ]
                    then
                        mv "$tmpVersion" "$fileName"
                        if [ "$?" == "0" ]
                        then
                            result=0
                        fi
                    fi
                fi
            fi
        fi
    else
        log_error "Fatal error in replacing file - check ${TMPDIR} is available and accessible"
    fi

    if [ "$result" == "1" ]
    then
        log_error "Failed to make replacement: '$searchStr' with '$replaceStr' in  $fileName. Got result: $result"
    elif [ "$result" == "2" ]
    then
        log_trace "Nothing to replace: '$searchStr' does not appear in  $fileName or $fileName does not exist"
    elif [ "$result" == "3" ]
    then
        log_trace "Replace string already present: '$replaceStr' already appears in  $fileName"
    fi
    return $result
}

########################################################################################################################
# Description:
# Replace the search string with the replacement in the file with optional backing up the original file.
# If the search string is not found the entry is appended to the file.
# If there is an error in replacement the backup is restored and the error is reflected (see 'replaceInFile')
# If creating the backup fails '255' is returned.
# Arg1: The string to search for.
# Arg1: The replacement
# Arg3: the file
# Return 0 if replacement successful or text was already there, otherwise 1 if there was an error
########################################################################################################################
function ensureInFile()
{
    local searchStr="$1"
    shift
    local replaceStr="$1"
    shift
    local fileName="$1"
    replaceInFileWithBackup "$searchStr" "$replaceStr" "$fileName" $@
    local result="$?"
    if [ "${result}" == "2" ]
    then
        echo "$replaceStr" >> "$fileName"
        if [ "$?" != 0 ]
        then
            result=1
        fi
    elif [ "$result" == "3" ]
    then
        # Text was already present
        result=0
    fi
    return ${result}
}

########################################################################################################################
# Description:
# Replace the search string with the replacement in the file with optional backing up the original file.
# If there is an error in replacement the backup is restored and the error is reflected (see 'replaceInFile')
# If creating the backup fails '255' is returned.
# Arg1: The string to search for.
# Arg1: The replacement
# Arg3: the file
# Return 0 if replacement successful, 1 if there was an error, 2 if no string was there to replace and 3 if what was
# being replaced was already there
########################################################################################################################
function replaceInFileWithBackup()
{
    local searchStr="$1"
    local replaceStr="$2"
    local fileName="$3"
    local includeBackup=true
    if [ $# -gt 3 ]
    then
        if [ "$4" == "NO_BACK_UP" ]
        then
            includeBackup=false
        fi
    fi
    local result=0
    local backupName=
    if $includeBackup
    then
        backupName=$(createBackupFile "$fileName")
        if [ "$?" != "0" ]
        then
            result=1
        fi
    fi

    if [ "$result" == "0" ]
    then
        replaceInFile "$searchStr" "$replaceStr" "$fileName" $backupName
        result="$?"
        if [[ "$result" == "1" && ! -z "$backupName" ]]
        then
            mv "$backupName" "$fileName"
        fi
    fi
    return $result
}

function getBackupFileName() {
    echo "$1-bkup-$(getDate)"
}

function createBackupFile()
{
    local fileName="$1"
    local backupName=$(getBackupFileName ${fileName})

    local savedVersion="${backupName}"
    local i=0
    while [ -e "$savedVersion" ]
    do
        i=$[$i+1]
        savedVersion="${backupName}.${i}"
    done

    cp "$fileName" "$savedVersion" > ${DEV_NULL} 2>&1
    echo "$savedVersion"
}
