#!/bin/bash
########################################################################################################################
# Takes a requirements yaml file and installs the galaxy roles to the required dir.
# The required dir by default is '/automation-incubator/ansible/roles' but if the requirements file is located in the
# same dir as an ansible.cfg file, the roles_path in the ansible.cfg file is taken in preference.
# All roles downloaded from galaxy are entered into a '.gitignore' file in the roles directory.
########################################################################################################################

[[ -z ${SCRIPT_PATH+x} || -z "$SCRIPT_PATH" ]] && SCRIPT_PATH=$(cd $(dirname "${BASH_SOURCE[0]}"); pwd)
[[ -z ${BASE_DIR+x} || -z "$BASE_DIR" ]] && BASE_DIR=$(cd ${SCRIPT_PATH}/..; pwd)

[[ $# == 0 ]] && { echo "Require path to requirements.yml file"; exit 1; }

REQUIREMENTS_FILE=$1
[[ ! -e ${REQUIREMENTS_FILE} ]] && { echo "Failed to find $REQUIREMENTS_FILE"; exit 1; }

ROLES_DIR="${BASE_DIR}/playbooks/roles"
ANSIBLE_CFG_FILE="${BASE_DIR}/ansible.cfg"
[[ ! -e "${ANSIBLE_CFG_FILE}" ]] && ANSIBLE_CFG_FILE="${BASE_DIR}/playbooks/ansible.cfg"

if [[ -e "${ANSIBLE_CFG_FILE}" ]]
then
    if grep -q roles_path $ANSIBLE_CFG_FILE
    then
        A_ROLES_DIR=$(grep roles_path ${ANSIBLE_CFG_FILE} | cut -d "=" -f 2 | tr -d '[:space:]')
        pushd $(diename ${ANSIBLE_CFG_FILE}) &> /dev/null
        [[ ! -d "${A_ROLES_DIR}" ]] && mkdir ${A_ROLES_DIR}
        ROLES_DIR=$(cd ${A_ROLES_DIR}; pwd)
        popd &> /dev/null
    fi
fi

GIT_IGNORE_FILE=${ROLES_DIR}/.gitignore

for role in $(grep 'src:' ${REQUIREMENTS_FILE} | awk '{print $3}')
do
	role_name=$(echo "$role" | awk -F '/' '{print $NF}' | awk -F '.' '{print $1}') 
	if ! grep -q ${role_name} ${GIT_IGNORE_FILE} 2>/dev/null
	then 
		echo ${role_name} >> ${GIT_IGNORE_FILE}
	fi
done

ansible-galaxy install --roles-path=${ROLES_DIR} -r ${REQUIREMENTS_FILE}
