#!/usr/bin/env bash
# AMQ 7.1
NAMESPACE=openshift
[[ $# -gt 0 ]] && NAMESPACE=$1

# To obtain following secret select 'Service Accounts' at 'https://catalog.redhat.com/software/containers/explore'
oc create secret -n ${NAMESPACE} docker-registry redhat-io-secret --docker-server=registry.redhat.io --docker-username='7417794|traininguser' --docker-password='eyJhbGciOiJSUzUxMiJ9.eyJzdWIiOiI2ZTBhMGM4MzdjNWM0ZjczYjJmZjM3ZmFmNWVhYjUxOSJ9.X0py9tjcM81bjJhRWPdNM5NUehu1NslasB8Y3tPd410AtPSlUwVA0IcIV66vlGx1sQSGLW-RDCnB5UjmDzn_mZk-3lNlViDT-CIaIuUDpDoK5rQy3dWLcV_hMAo48rEZ0UKAQryRbzIvSZTwyOm7SZWzXC4P8JQ7ceMj6ThcInMf9cA-O02m7BqS1TGMz12eeD73TIX0TDHO0Ffn8Yj9LMXC-LJXJRWT5KvcX4mBbZnSgYDLqfcB2h33hdfcyvBibe6RzqlOGLbQSvkO-mH3bIQTZTjBVLXcrcRdnw4rcXqsXcUZitl1Z_2jz3-J5l0quXFUC581gWfRFy55euZRL73zBS5NjiNylVQWyAhdnEeztmMFps79JG_AMj2m6eXIdBhXjxmecwaDV0rbz8gb5rHon0KmsQBLIqlIj4_BxrD2kN-lwtoGRFWSva6iWShQ8DRQB_cU2-t6yg0WfzTKZRYSbHCSQ8RhhFmYctxily42wh3NFg98nQoPLrKA0FeZqY9VRt2pWTb-7wD6_znsktdqSlx4aKAro5n3tjtL_fVkL8eu4iAE7ATxlql4bmnh2863SawJtQpyCErzgEORRiv3jiSs6BBZ81oBTv7xub6bLSE9QCc_zHrTW2FqY6kDJ3PifIC6noNbrHe2YDKLHbxfEqg7GpDkffFOfSw5VGs' --docker-email='dstewart@redhat.com'

oc import-image -n ${NAMESPACE} amq7/amq-interconnect:1.3 --from=registry.redhat.io/amq7/amq-interconnect:1.3 --confirm
oc import-image -n ${NAMESPACE} amq7/amq-interconnect:1.4 --from=registry.redhat.io/amq7/amq-interconnect:1.4 --confirm
oc import-image -n ${NAMESPACE} amq7/amq-interconnect:1.5 --from=registry.redhat.io/amq7/amq-interconnect:1.5 --confirm
oc import-image -n ${NAMESPACE} amq7/amq-interconnect:1.6 --from=registry.redhat.io/amq7/amq-interconnect:1.6 --confirm
oc import-image -n ${NAMESPACE} amq7/amq-interconnect --from=registry.redhat.io/amq7/amq-interconnect --confirm

oc import-image -n ${NAMESPACE} amq7/amq-broker:7.4 --from=registry.redhat.io/amq7/amq-broker:7.4 --confirm
oc import-image -n ${NAMESPACE} amq7/amq-broker:7.5 --from=registry.redhat.io/amq7/amq-broker:7.5 --confirm
oc import-image -n ${NAMESPACE} amq7/amq-broker --from=registry.redhat.io/amq7/amq-broker --confirm

# load old amq-broker images
# AMQ 7.1
oc create -n ${NAMESPACE} -f https://raw.githubusercontent.com/jboss-container-images/jboss-amq-7-broker-openshift-image/71-1.0.TP/amq-broker-7-image-streams.yaml
oc replace -n ${NAMESPACE} --force -f https://raw.githubusercontent.com/jboss-container-images/jboss-amq-7-broker-openshift-image/71-1.0.TP/amq-broker-7-image-streams.yaml

# AMQ 7.2
oc create -n ${NAMESPACE} -f https://raw.githubusercontent.com/jboss-container-images/jboss-amq-7-broker-openshift-image/72-1.2.GA/amq-broker-7-image-streams.yaml
oc replace --force -f https://raw.githubusercontent.com/jboss-container-images/jboss-amq-7-broker-openshift-image/72-1.2.GA/amq-broker-7-scaledown-controller-image-streams.yaml
