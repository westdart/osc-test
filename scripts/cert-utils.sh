#!/usr/bin/env bash

function getCertificatesFromServer()
{
    local host=$1
    local port=$2

    echo -n | openssl s_client -connect ${host}:${port} -servername ${host} -showcerts 2>/dev/null | \
      sed --quiet '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p'
}

function addTrustedCerts()
{
    local host=$1
    local port=$2
    sudo /bin/bash -c "echo \"$(getCertificatesFromServer $host $port)\" > /etc/pki/ca-trust/source/anchors/${host}.pem"
}

function updateDockerTrust()
{
    sudo update-ca-trust &&
      sudo /bin/systemctl restart docker.service
}

function showCertificateHostName()
{
    local host=$1
    local port=$2

    local entry=
    for entry in $(getCertificatesFromServer $host $port | openssl x509 -nocert -text -certopt no_subject,no_header,no_version,no_serial,no_signame,no_validity,no_issuer,no_pubkey,no_sigdump,no_aux | grep 'DNS:')
    do
        local host=$(echo ${entry} | awk -F ':' '{print $2}' | awk -F ',' '{print $1}')
        [[ ! -z "${host}" ]] && echo ${host}
    done
}

function hostnameInCertificate()
{
    local host=$1
    local port=$2
    local hostname=$host
    [[ $# -gt 2 ]] && hostname=$3

    showCertificateHostName $host $port | grep -q "^${hostname}$"
}

# If script is not being sourced, execute whatever is being passed
if [[ $0 == ${BASH_SOURCE[0]} ]]
then
    if grep -q "^function $1" ${BASH_SOURCE[0]} 2>/dev/null
    then
        ${@}
    else
        echo "First arg must be a function followed by its arguments"
    fi
fi
