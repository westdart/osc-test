# Setting up External Registry and Accessing Images

This readme covers the steps required to:
- setup a cluster access to a remote registry including:
  - building cluster from scratch with access
  - configuring certificate trust store
- setup a project to access the remote registry
  - obtaining pull secrets to a Registry
  - configuring pull secrets
- setup a deployment to pull images from remote registry
  - Direct sourced image from remote registry
  - Direct sourced image from remote registry's ImageStream
  - Sourced image through internal ImageStream

This does not cover the setting up of the external registry.
  
# Cluster Setup
Adding External registries to the cluster can be done at installation
or added subsequently.

## From Installation
External registries that need to be accessed can be added during 
OpenShift installation or upgrade by providing the 
'openshift_additional_registry_credentials' ansible variable, e.g.:
```
openshift_additional_registry_credentials=[
  {'host':'registry.example.com','user':'name','password':'pass1','test_login':'False'},
  {'host':'registry2.example.com','password':'token12345','tls_verify':'False','test_image':'mongodb/mongodb'}]
```

Coupled with /etc/containers/registries.conf ?
Would that work?

## Adding an External Registry to existing Installation

There two parts to this, first ensuring that the external registry cert
is trusted and second creating the pull secret in the target namespace.

### Updating the trust store
The playbook 'update-registry-certs.yml' covers these actions.

This consists of two plays, one running 'localhost' and obtaining the
required certificate, and one running on target machines to update them
with the certificate.

As such both the external registry and the target systems need to be 
accessible to the machine that ansible runs on.

To access the target machines, the ansible inventory is relied upon, but
the external repository must be provided as a variable 'external_registry'
containing both the host name and port of the registry.

e.g.
```
$ ansible-playbook -i <innventory> --extra-vars "target=all" \
    --extra-vars '{"external_registry": { "host": "docker-registry-default.t2.training.local", port: "443"}}' \
    playbooks/update-registry-certs.yml
```

As the registry needs to be accessible by all nodes that pull images,
the target can be simply put as 'all'. If a more narrow targeting is 
required, see the inventory for the relevant groups.

# Setting up a project 
## Creating users and secrets in an OpenShift Registry to enable external access
Within the project that the images are to be held a service account can be created.
By default this will be setup with a secret to enable pull operations
in the Registry for the specific namespace.

If 'push' operations are required, the user should be modified to allow
it to edit the namespace, ie.:
```
$ oc adm policy add-role-to-user edit -z <service-account> -n <namespace>
```

To obtain a cluster wide push access the following role should be added
to the user:
```
$ oc policy add-role-to-user system:image-builder -z <service-account>
```

### Creating the pull secret in the target Openshift Cluster
This playbook simply runs 'localhost' using oc commands to effect the 
changes.

A vault file path must be provided which must conform with the following format:

```
---
openshift_login_credentials:
  'https://t1-master.openshift.local:8443':
    openshift_user: 'admin'
    openshift_password: 'password'
  'https://t2-master.openshift.local:8443':
    openshift_user: 'admin'
    openshift_password: 'password'
registry_login_credentials:
  'docker-registry-default.t2.training.local':
   - secret_name: 't2-registry-credential'
     username: 'reggieperrin'
     token: 'eyJhbGciOiJSUzI1NiIsImtpZCI6IiJ9.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJpbWducyIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJyZWdnaWVwZXJyaW4tdG9rZW4tZjdudmsiLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlcnZpY2UtYWNjb3VudC5uYW1lIjoicmVnZ2llcGVycmluIiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZXJ2aWNlLWFjY291bnQudWlkIjoiY2Q1YmQ0ZWEtNDg2Yy0xMWVhLWI0ODgtMDY5NmE0NTE1YTEwIiwic3ViIjoic3lzdGVtOnNlcnZpY2VhY2NvdW50OmltZ25zOnJlZ2dpZXBlcnJpbiJ9.dZF0AUU7ixGsT0phwnEhi842vPowTngLwFtiPEQJapErJPsjdJnzQr6OIlYoxq2MXLUAPQfBu13owpU3-1Lwp8gew0PUqsvFrXmDZUv9e8EqFL5LAn45y5kTpFajufii7lu4YlqwTuvyXBEsQtM4k7OYUfV0uSpYNmh5ZswAXLh_Z85GP52mIWOjgbbsCRs1g3F9bALButN3kJ4ltX678KQ7eLcyEBonMmg_MKRjy4kZtotQ5GGSqu2ge8hez567mvNZZoNSvjselO1GbUsUZoYWFgMwdHD1YDVGkuS9RjX4wBuMxOJMQ9wkbblfLhO05ELfVNwSQLdZc6DhjuwcJA'
   - secret_name: 't2-registry-push-credential'
     username: 'charlesjefferson'
     token: 'eyJhbGciOiJSUzI1NiIsImtpZCI6IiJ9.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJpbWducyIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJjaGFybGVzamVmZmVyc29uLXRva2VuLTV4cWQ2Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZXJ2aWNlLWFjY291bnQubmFtZSI6ImNoYXJsZXNqZWZmZXJzb24iLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlcnZpY2UtYWNjb3VudC51aWQiOiI4OTA5Y2NjOS00OTAyLTExZWEtOGRkNy0wNjk2YTQ1MTVhMTAiLCJzdWIiOiJzeXN0ZW06c2VydmljZWFjY291bnQ6aW1nbnM6Y2hhcmxlc2plZmZlcnNvbiJ9.MmqO-1Jxy_FlCYa0w8oOa-xh3lPr5WmVTD8bLVJ7g_ZHwSFGF0fnjZZH4-7PTcn2HxoIl_GkODO28laM3BYkQkeNMpYE76H5b1zoSCx_6qzBTJNZphK-oBlSwiZifUNHpiGB1Ai39kC47ryvnPBoejiqLn_YrMrhO8iMABCv-PLTd2L-y0cAezwb7rONmqjosq9Em2QWqBw1GghXxzRB3GVw8TngK5MrymSUfxneK1loPCotDMNORvxboASu08ZFxahhl7CzYeYWvjGwzJVEBdY5R4oKgZoaGVIlMW8dh75_zwFOElyE1l9SnxBskMV4xTfhsJTgZ1FqyNe2LW17PA'
     operation: 'push'

``` 

Note, the 'registry_login_credentials' entry users must have 'get' 
rights on the required images in the external registry, or if push is 
required, 'update' rights. If using an OpenShift external registry, all
service accounts have 'get' access to the same project and the 'builder'
system user has 'update' rights in the same project. (See above for 
setting users on an Openshift external registry)  

This enables both login to the Openshift platform and docker registries.
In the case where a docker registry is in fact an OpenShift internal
registry, the 'openshift_url' key should be included pointing to the
'openshift_login_credentials' entry to enable the correct credentials to 
be established.

The 'oc_login_url' is the url to the cluster that requires the secret 
creating and must match with an 'openshift_login_credentials' entry in 
the vault.

The 'registry_server' var must match with a 'registry_login_credentials'
entry in the vault and point to the external registry required.

The 'registry_secret_namespace' is simply the namespace in which to 
create the secret in the 'oc_login_url' cluster.

e.g.
```
$ ansible-playbook --extra-vars "@~/.vaults/openshift-credentials.vault" \
    --extra-vars 'oc_login_url=https://t1-master.openshift.local:8443' 
    --extra-vars 'registry_server=docker-registry-default.t2.training.local' 
    --extra-vars 'registry_secret_namespace=dif-dev' 
    --vault-id appcred@../pwd.txt playbooks/add-registry-secret.yml
```

# Doing Deployments
What has been covered so far is enough to configure deployments with 
images located in the external registry.

If pulled directly as images, they will not be cached on the local 
cluster and therefore will require access to the external registry when 
pods are started.

To speed up deployment and make it more resilient to external registry
outages, ImageStreams can be set up to 'pull through' the image, leaving
a cached version in the internal OpenShift registry.

