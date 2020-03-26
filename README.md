# Platform Setup

This is a test project that can be used as a sample to launch builds.

## Overview
This project is a launch pad for the ar_osc roles. It demonstrates what 
a playbook should look like for each of the Openshift Container 
Application Roles.

There is a preparation phase for setting up sensitive information 
required by the roles and then a deployment phase, where each role can 
be invoked and the application deployed to a target.

## Requirements
The machine running ansible must also have the Openshift Client 'oc' installed.

## Dependencies
Relies on openshift-applier, casl-ansible and ar_oas application roles. 
To obtain execute the following:
```
$ .scripts/update_galaxy_dependencies.sh roles/requirements.yml
```

## Preparation

As a pre-cursor to running application playbooks, CAs, TLS keys, certs, 
SSH keys and secrets need to be created for use in the playbooks.

To set these up run the following script:
```
# ./scripts/build.sh -p password -i <app-instances file> -f prepare
```

This script invokes the following playbooks:

- generate-secrets.yml
- setup-tls.yml

Note: Re-running the 'generate-secrets.yml' does not update the ansible 
vault after creation. A process is needed that enables instances to be 
added whilst maintaining the current secrets unchanged. A manual 
workaround for this is to take a backup of the file, regenerate a new
vault and then manually replace the existing vault contents into the 
new vault contents.

The 'app-instances' file and associated content (generated and required)
can be held in a separate git repository as can the TLS artefacts that
are generated. These git repos must already exist with references to 
them configured in the app-instances file (see sample).

## Deployment

Note: The user executing the script must be logged into the correct 
Openshift cluster that the deployment is required in.

To deploy all applications to a specific target:
```
# ./scripts/build.sh -t <target> -p <password> -i <app-instances file>
```

This invokes the following playbooks:
- amq-broker.yml
- amq-interconnect.yml
- aspera.yml
- git-checkin.yml

The first three build the config and deploy the respective applications
for the required target. The 'git-checkin.yml' ensures that any changes
to the generated config are checked into git.

Each can be invoked separately using the '-f' parameter and the function
of the script that should be executed, e.g.
```
# ./scripts/build.sh -t <target> -p <password> -i <app-instances file> -f amq_broker
# ./scripts/build.sh -t <target> -p <password> -i <app-instances file> -f amq_interconnect
# ./scripts/build.sh -t <target> -p <password> -i <app-instances file> -f aspera
# ./scripts/build.sh -t <target> -p <password> -i <app-instances file> -f checkin
```

Each of the ar_osc aplication roles is created in a similar way, with 6 
or 7 stages:
 
| Stage          | Description                                                                 |
| -----          | -----------                                                                 |
| docker         | (Aspera only) Build and push Docker images                                  |
| config         | Generate the config for application                                         |
| secrets        | Provide secrets used by the application in form digestible by process       |
| seed           | Generate the Ansible inventory and seed-hosts for driving openshift-applier |
| apply          | Apply the config using openshift-applier                                    |
| label          | Any additional labelling of Openshift objects                               |
| remove-secrets | remove any sensitive information from file system                           |
 
Any of the stages can be executed separately using:
```
# ./scripts/build.sh -t <target> -p <password> -i <app-instances file> --extra-vars "selected_tasks=<stage>" -f <app>
```
Where:
- <stage> is one of the stages above
- <app> is the bash function that invokes the specific ar_osc 
application role (e.g. 'amq_broker', 'amq_interconnect' or 'aspera')


As part of the Aspera deployment, Docker images are built. This can take
some time and is only required once per destination repository. To skip
the docker build add:
```
   --skip-tags docker
```
i.e.
```
# ./scripts/build.sh -t <target> -p <password> -i <app-instances file> --skip-tags docker
or
# ./scripts/build.sh -t <target> -p <password> -i <app-instances file> --skip-tags docker -f aspera
```

To just invoke the build of Docker images execute:
```
# ./scripts/build.sh -t <target> -p <password> -i <app-instances file> --extra-vars "selected_tasks=docker" -f aspera
```

## Sample
A sample vars file is provided in the 'osc_environments' git repository

# Setting up passphrases
The script operates on an encrypted file to obtain passphrases to the required vaults etc.

To set this up the following functions should be used:
```
# export SECRET_PASSPHRASE=$(./scripts/build.sh -f getConfirmedPassword Enter passphrase)
# ./scripts/build.sh -f setupSecrets
```
The first puts the secret used to encrypt the data into the environment
(without entering it into the command literally and hence into history).
The second prompts for each of the required secrets in turn and creates
the secret file (at ~/.secrets) 

# Setting up OC Login credentials
Ansible vaults are used to store the OpenShift login credentials.

To set up, create an ansible vault (this will contain one or more sets of credentials for OpenShift clusters)
```
# ansible-vault create ~/.vaults/openshift-credentials.vault
# chmod 700 ~/.vaults
# chmod 600 ~/.vaults/openshift-credentials.vault
```

The contents should reflect the following:
```
---
openshift_login_credentials:
  '<the console url - i.e. <protocol>://<host>:<port>>':
    openshift_user: '<the user>'
    openshift_password: '<the password>'
```
With an entry under 'openshift_login_credentials' for each cluster that needs to be accessed.

# Setting up GIT credentials

Obtain a bas64 encoded private ssh key:
```
# b64key=$(ansible-playbook playbooks/show-b64encoded-file.yml --extra-vars "thefile=<private-key-path>" | grep msg | awk -F '"' '{print $(NF-1)}')
```

Obtain the plain text file to be encrypted:
```
# echo -e "git_credentials:\n  '<git-repo-url>':\n    ssh_key: '${b64key}" > playbooks/gitcredentials.vault
```

Vault the file:
```
# ansible-vault encrypt playbooks/gitcredentials.vault
```

# Build Sequence

```
# export GIT_URL=ssh://git@estafet.repositoryhosting.com/estafet
# export ENV=DEV
# echo "my credential vault passphrase" > ~/.vaults/cred.txt
# echo "my app vault passphrase" > ~/.vaults/app.txt
# echo "my git vault passphrase" > ~/.vaults/git.txt
```
Remove existing secrets and keys:
```
# ansible-playbook --extra-vars "git_repo_url=${GIT_URL}/osc_environments.git" \
                   --extra-vars "environment_name=${ENV}" \
                   --vault-id cred@~/.vaults/cred.txt \
                   --vault-id app@~/.vaults/app.txt \
                   --vault-id app@~/.vaults/git.txt \
                   --extra-vars 'reset_secrets=true' \
                   playbooks/reset-secrets.yml
```

Setup keys and secrets:
```
# ansible-playbook --extra-vars "git_repo_url=${GIT_URL}/osc_environments.git" \
                   --extra-vars "environment_name=${ENV}" \
                   --vault-id cred@~/.vaults/cred.txt \
                   --vault-id app@~/.vaults/app.txt \
                   --vault-id app@~/.vaults/git.txt \
                   playbooks/prepare.yml
```

Build AMQ:
```
# export TARGETS='"CENTRAL"'
# ansible-playbook --extra-vars "git_repo_url=${GIT_URL}/osc_environments.git" \
                   --extra-vars "environment_name=${ENV}" \
                   --vault-id cred@~/.vaults/cred.txt \
                   --vault-id app@~/.vaults/app.txt \
                   --vault-id app@~/.vaults/git.txt \
                   --extra-vars '{"targets": ['${TARGETS}']}' \
                   playbooks/amq-broker.yml
```

Build Interconnect:
```
# export TARGETS='"MESH","CENTRAL"'
# ansible-playbook --extra-vars "git_repo_url=${GIT_URL}/osc_environments.git" \
                   --extra-vars "environment_name=${ENV}" \
                   --vault-id cred@~/.vaults/cred.txt \
                   --vault-id app@~/.vaults/app.txt \
                   --vault-id app@~/.vaults/git.txt \
                   --extra-vars '{"targets": ['${TARGETS}']}' \
                   playbooks/amq-interconnect.yml
```

Build Aspera:
```
# export TARGETS='"CENTRAL"'
# ansible-playbook --extra-vars "git_repo_url=${GIT_URL}/osc_environments.git" \
                   --extra-vars "environment_name=${ENV}" \
                   --vault-id cred@~/.vaults/cred.txt \
                   --vault-id app@~/.vaults/app.txt \
                   --vault-id app@~/.vaults/git.txt \
                   --extra-vars '{"targets": ['${TARGETS}']}' \
                   playbooks/aspera.yml
```

# Teardown
In order to completely test everything it is necessary to reset the 
current environment, i.e.

1. Delete projects in Openshift, or remove using appgroup label (oc delete -l 'appgroup=<label, e.g. central>' all,pvc,secret,cm)
2. Execute the reset-secrets playbook
3. Delete the CA driectory in the tls ca git repository (referenced
in the 'app-environment.yml' file in the git repository used in the
'ar_os_environment' role)

# Rebuild
Use the following steps to rebuild

| Playbook         | Verification                                                                                                                                                                                                                                                                                                                                                                                    |
| -----            | -----------                                                                                                                                                                                                                                                                                                                                                                                     |
| prepare          | On success, a new 'app-environment.vault' file should have been created and certificates placed in the 'generated/certs' directory in the git repository used in 'ar_os_environment'. Those certificates must match those stored in the tls ca git repository in the '<ca-name>/out' directory. Also those certificates should correspond to the keys held in the 'app-environment.vault' file. |
| amq-broker       | Check log files for errors, Check message transfers between brokers via interconnects using Broker console to send messages from Central to Deployed and visa versa                                                                                                                                                                                                                             |
| amq-interconnect | Check log files for errors, Check message transfers between brokers via interconnects using Broker console to send messages from Central to Deployed and visa versa                                                                                                                                                                                                                             |
| aspera           | Run the aspera-test.sh script and ensure all tests pass                                                                                                                                                                                                                                                                                                                                         |
