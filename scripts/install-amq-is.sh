#!/usr/bin/env bash
# AMQ 7.1
oc create -n openshift -f https://raw.githubusercontent.com/jboss-container-images/jboss-amq-7-broker-openshift-image/71-1.0.TP/amq-broker-7-image-streams.yaml
oc replace -n openshift --force -f https://raw.githubusercontent.com/jboss-container-images/jboss-amq-7-broker-openshift-image/71-1.0.TP/amq-broker-7-image-streams.yaml
oc -n openshift import-image amq-broker-71-openshift:1.0
for template in amq-broker-71-basic.yaml \
amq-broker-71-ssl.yaml \
amq-broker-71-persistence.yaml \
amq-broker-71-persistence-ssl.yaml \
amq-broker-71-statefulset-clustered.yaml;
 do
 oc create -n openshift -f \
https://raw.githubusercontent.com/jboss-container-images/jboss-amq-7-broker-openshift-image/71-1.0.TP/templates/${template}

 oc replace -n openshift -f \
https://raw.githubusercontent.com/jboss-container-images/jboss-amq-7-broker-openshift-image/71-1.0.TP/templates/${template}
 done

# AMQ 7.2
oc create -n openshift -f https://raw.githubusercontent.com/jboss-container-images/jboss-amq-7-broker-openshift-image/72-1.2.GA/amq-broker-7-image-streams.yaml
oc replace --force -f https://raw.githubusercontent.com/jboss-container-images/jboss-amq-7-broker-openshift-image/72-1.2.GA/amq-broker-7-scaledown-controller-image-streams.yaml
oc import-image amq-broker-72-openshift:1.2
oc import-image amq-broker-72-scaledown-controller-openshift:1.0
for template in amq-broker-72-basic.yaml \
amq-broker-72-ssl.yaml \
amq-broker-72-custom.yaml \
amq-broker-72-persistence.yaml \
amq-broker-72-persistence-ssl.yaml \
amq-broker-72-persistence-clustered.yaml \
amq-broker-72-persistence-clustered-ssl.yaml;
 do
 oc replace --force -f \
https://raw.githubusercontent.com/jboss-container-images/jboss-amq-7-broker-openshift-image/72-1.2.GA/templates/${template}
 done

# AMQ IC
oc import-image amq-interconnect:latest -n openshift --from=registry.access.redhat.com/amq7/amq-interconnect --confirm
curl https://raw.githubusercontent.com/jboss-container-images/amq-interconnect-1-openshift-image/amq-interconnect-1.3/templates/amq-interconnect-1-basic.yaml | oc create -f -
curl https://raw.githubusercontent.com/jboss-container-images/amq-interconnect-1-openshift-image/amq-interconnect-1.3/templates/amq-interconnect-1-tls-auth.yaml | oc create -f -
curl https://raw.githubusercontent.com/jboss-container-images/amq-interconnect-1-openshift-image/amq-interconnect-1.3/templates/amq-interconnect-1-sasldb-auth.yaml | oc create -f -

