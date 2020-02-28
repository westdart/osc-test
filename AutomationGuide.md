# Automation Guide

## Roles

The following Ansible roles have been created:

General OpenShift related Ansible Roles: 

- ar_os_registry_secret: Creates secrets and links to either 'default' or 'builder' system account depending on the purpose of the secret
- ar_os_secret_link: Links secrets to a Service Account
- ar_os_scc_binding: Binds Security Contect Constraints to Service Accounts
- ar_os_seed: Wrapper around openshift-applier, this generates a group-vars file to drive the applier to create ovjects in Openshift
- ar_os_common: Holds various sets of tasks that enable quick development of features that are required.
  - get-cert.yml: Obtain a certificate chain from a server (calls validate-cert.yml)
  - login.yml: Login to OpenShift. Ensures forced login when required (calls casl-ansible/roles/openshift-login)
  - place-registry-cert.yml: Copies registry certs to required location on target hosts and triggers update-ca-trust and docker restarts
  - place-docker-certs.yml: Only used on Docker version < 1.13 - adds the certs to the docker configuration
  - registry-list.yml: Outputs list of upstream registries to '/etc/containers/registries.update(!conf)' (untested) 
  - validate-cert.yml: Validate a certificate for expiry and hostname applicability
 
Application Specific Ansible Roles:

- ar_osc_amqbroker
- ar_osc_amqinterconnect
- at_osc_aspera

Non-OpenShift related roles:

- ar_tls_ca


### Service Accounts

A common set of data objects are required to drive these roles.
The following is a description of those data objects with references to 
the respective roles.

- List of Service Accounts:
```
serviceaccounts: [
  {
    sa_name: ... *,**                 Service Account Name
    scc: ... *                        Security Contect Constraint
    link_secrets: [ ***               List of Secrets
      {
        secret_name: ... **           Secret Name
        server: ...                   Associated Server
        username: ...                 User associated with the secret
        password: ...                 Password for the user
        token: ...                    Token created for the user
        operation: ... **             Type of operation ('pull' or 'push')
      }, ... 
    ]     
  }, ...
]
```
- Associated Roles:
```
*   ar_os_scc_binding
**  ar_os_secret_link
*** ar_os_registry_secret
```

### Openshift Login

Login to Openshift is handled by the 'login' tasks within ar_os_common.
Although the roles do not mandate it, the credentials can be passed in
using another data object:

Openshift Login credentials
```
openshift_login_credentials:
  '<full login url>':
    openshift_user: '<the username>'
    openshift_password: '<optional password for the user>'
    openshift_token: '<optional auth token for the user>'
```
Either the 'openshift_password' or the 'openshift_token' must be provided.

Even though the user information is immaterial when logging in with a 
token, it serves a purpose in giving the token a reference.

### External Registry Credentials

An additional set of credentials should be provided if an external 
container registry is being used. This gives the required access 
credentials for such a service.
```
registry_login_credentials:
  '<hostname of external registry being accessed>':
   - secret_name: '<name to ascribe to any secret being created for these credentials'
     username: '<the username for the external registry>'
     password: '<optional password for the user>'
     token: '<optional auth token for the user>'
     operation: '<type of operation, currently either "pull" (default) or "push">'
``` 
