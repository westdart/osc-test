# ar_osc_test

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
# ./scripts/build.sh -t <target> -p <password> -i <app-instances file> --extra-vars "tasks=<stage>" -f <app>
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
# ./scripts/build.sh -t <target> -p <password> -i <app-instances file> --extra-vars "tasks=docker" -f aspera
```

## Sample
A sample vars file is provided in the 'osc_environments' git repository
