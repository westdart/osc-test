#!/usr/bin/env bash
########################################################################################################################
# Common property functions
########################################################################################################################
SECRET_FILE=~/.secrets
SECRET_FILE_BKUP=${SECRET_FILE}.bkup
##############################################################################
# Description:
# Get a property value from a property tuple.
# Arg1: The tuple
# Return 0.
##############################################################################
function extractPropertyValue() {
    local tuple="$1"
    log_trace "extractPropertyValue: tuple: $tuple"
    local equalsPos=`expr index "${tuple}" "="`
    local value=`echo ${tuple:$equalsPos}`
    log_trace "extractPropertyValue: returning value: $value"
    [ -z "$value" ] && return
    echo "$(trim $value)"
}

##############################################################################
# Description:
# Get a property key from a property tuple.
# Arg1: The tuple
# Return 0.
##############################################################################
function extractPropertyKey() {
    local tuple=$1
    local equalsPos=`expr index "${tuple}" "="`
    echo ${tuple:0:$equalsPos-1}
}

##############################################################################
# Description:
# Get a property directly from a file or parameter. If the Arg1 parameter
# is a file then obtain the property from it otherwise treat it as the file
# contents and obtain the property directly from it.
# Arg1: The file name or property set
# Arg2: The property key
##############################################################################
function getRawProperty() {
    local func="egrep"
    local data=
    local tuple=
    if [ $# -gt 2 ]
    then
        func="$3"
    fi

    if [ -e "$1" ]
    then
        data=`cat "$1"`
    else
        data="$1"
    fi
    local key=$(escapeRegex "${2}")
    log_trace "getRawProperty: key: $key"
    log_trace "data=$data"
    tuple=$(echo "$data" | sed '/^\#/d' | $func "^${key}[[:space:]]*=" | tail -n 1)
    extractPropertyValue "$tuple"
}

##############################################################################
# Description:
# Set a property directly in a file or parameter. If the Arg1 parameter
# is a file then obtain the property from it otherwise treat it as the file
# contents and obtain the property directly from it.
# Arg1: The file name or property set
# Arg2: The property key
# Arg2: The property value
##############################################################################
function setRawProperty() {
    local func="egrep"
    local data=
    local name=$2
    local value=$3
    local update=false

    if [ $# -gt 3 ]
    then
        func="$4"
    fi

    if [ -e "$1" ]
    then
        data=`cat "$1"`
    else
        data="$1"
    fi
    local currentValue=
    currentValue=$(getRawProperty "$data" $name $func)

    if [ -z "$currentValue" ]
    then
        data="${data}
${name}=${value}"
        update=true
    else
        [ "$currentValue" != "$value" ] && { data=$(echo "$data" | sed 's#'$name'=.*#'$name'='$value'#g'); update=true; }
    fi

    $update && { echo "$data"; return 0; }
    return 1
}

function getRubyProperty() {
    local key="$(escapeDollar ${2})"
    local value=
    value=$(getRawProperty "$1" "$key")
    [ -z "$value" ] && { log_error "Failed to obtain value for $2"; log_trace "Data provides: $1"; return 1; }

    # Is the string quoted
    if startsWith "$value" '"' || startsWith "$value" "'"
    then
        if startsWith "$value" "'"
        then
            value=${value#"'"}
            value=${value%"'"}
        else
            value=${value#'"'}
            value=${value%'"'}
        fi
    fi

    echo $value
}

function getRawKeys() {
    local func="grep"
    local data=
    local tuple=
    if [ $# -gt 2 ]
    then
        func="$3"
    fi

    if [ -e "$1" ]
    then
        data=`cat "$1"`
    else
        data="$1"
    fi

    local keyFilter="^.*"
    if [ $# -gt 1 ]
    then
        keyFilter="$2"
    fi

    echo -e "$data" | sed '/^\#/d' | $func "$keyFilter=.*$" | awk -F "=" '{print $1}' | sort
}

function getERawKeys() {
    local keyFilter="^.*"
    if [ $# -gt 1 ]
    then
        keyFilter="$2"
    fi

    getRawKeys "$1" "$keyFilter" "egrep"
}

function getRawValues() {
    local data=
    if [ -e "$1" ]
    then
        data=`cat "$1"`
    else
        data="$1"
    fi

    local valueFilter=".*$"
    if [ $# -gt 1 ]
    then
        valueFilter="$2"
    fi

    echo -e "$data" | sed '/^\#/d' | grep "^.*=$valueFilter" | awk -F "=" '{print $2}'
}

##############################################################################
# Description:
# Merge a string with another string that holds java like properties
# Arg1: The string that has the propertiy replacement placeholders
# Arg2: The property replacements
# Return 0.
##############################################################################
function merge() {
    local source="$1"
    local replacements="$2"

    local propertyKeys=$(getERawKeys "$replacements")
    local key=
    for key in $propertyKeys
    do
        local value=
        value=$(escapeAmpersand $(escapeSlash $(getERawProperty "$replacements" "$key")))
        log_trace "Replacing '\${${key}}' with '${value}'"
        source=$(echo "$source" | sed 's/${'"${key}"'}/'"${value}"'/g')
        [ "$?" != "0" ] && { log_error "Failed effect a replacement: \${${key}} with '${value}'"; return 1; }
    done
    echo "$source"
}

function storeSecret()
{
    local name=
    local secret=
    local content=
    local newContent=

    if [ -z "${SECRET_PASSPHRASE+x}" ]
    then
        if [ ! -e $SECRET_FILE ]
        then
            SECRET_PASSPHRASE=$(getConfirmedPassword "Enter encryption passphrase") || { log_error "Could not obtain passphrase"; return 1; }
        else
            SECRET_PASSPHRASE=$(getPassword "Enter encryption passphrase") || { log_error "Could not obtain passphrase"; return 1; }
        fi
    fi

    if [ $# -gt 0 ]
    then
        name=$1
    else
        name=$(getInput "Enter secret name") || { log_error "Could not obtain secret name"; return 1; }
    fi

    secret=$(getConfirmedPassword "Enter '$name' secret") || { log_error "Could not obtain secret"; return 1; }

    if [ -e $SECRET_FILE ]
    then
        content=$(cat "$SECRET_FILE" | openssl enc -d -aes-256-cbc -a -salt -pass pass:${SECRET_PASSPHRASE} 2>/dev/null) || { log_error "Could not decrypt current secret file with passphrase"; return 1; }
        cp $SECRET_FILE ${SECRET_FILE_BKUP}
    fi
    newContent=$(setRawProperty "$content" $name $secret) || { log_info "Secret already present"; return 0; }

    echo -n "$newContent" | openssl enc -e -aes-256-cbc -a -salt -pass pass:${SECRET_PASSPHRASE} > "$SECRET_FILE" 2>/dev/null
    if [ $? != 0 ]
    then
        log_error "Failed to encrypt the secret file"
        [ -e "${SECRET_FILE_BKUP}" ] && mv $SECRET_FILE_BKUP $SECRET_FILE
        return 1
    else
        [ -e "${SECRET_FILE_BKUP}" ] && rm -f $SECRET_FILE_BKUP
    fi
    return 0
}

function getSecret()
{
    local name=
    local content=
    local result=

    if [ $# -gt 0 ]
    then
        name=$1
    else
        name=$(getInput "Enter secret name") || { log_error "Could not obtain secret name"; return 1; }
    fi

    if [[ -f $SECRET_FILE ]]
    then
        if [ -z "${SECRET_PASSPHRASE+x}" ]
        then
            SECRET_PASSPHRASE=$(getPassword "Enter encryption passphrase") || { log_error "Could not obtain passphrase"; return 1; }
            export SECRET_PASSPHRASE
        fi
        content=$(cat "$SECRET_FILE" | openssl enc -d -aes-256-cbc -a -salt -pass pass:${SECRET_PASSPHRASE} 2>/dev/null)
        if [ $? != 0 ]
        then
            log_error "Failed to decrypt the secret file"
            unset SECRET_PASSPHRASE
            SECRET_PASSPHRASE=
            return 1
        fi

        result=$(getRawProperty "$content" $name)
        if [ -z "$result" ]
        then
            log_error "Secret '$name' does not exist"
            return 1
        fi
        echo $result
    else
        log_error "Could not obtain secret $name, no secret file found"
        return 1
    fi
}

function haveSecret()
{
    local name=
    local content=
    local result=

    if [ $# -gt 0 ]
    then
        name=$1
    else
        name=$(getInput "Enter secret name") || { log_error "Could not obtain secret name"; return 1; }
    fi
    getSecret ${name} &> /dev/null
}

function showSecrets()
{
    if [[ ! -f $SECRET_FILE ]]
    then
        log_error "No secret file found at $SECRET_FILE"
    else
        if [ -z "${SECRET_PASSPHRASE+x}" ]
        then
            SECRET_PASSPHRASE=$(getPassword "Enter encryption passphrase") || { log_error "Could not obtain passphrase"; return 1; }
        fi
        content=$(cat "$SECRET_FILE" | openssl enc -d -aes-256-cbc -a -salt -pass pass:${SECRET_PASSPHRASE} 2>/dev/null)
        if [ $? != 0 ]
        then
            log_error "Failed to decrypt the secret file"
            SECRET_PASSPHRASE=
            return 1
        fi
        export SECRET_PASSPHRASE
        log_always "Secrets:${content}"
    fi
}