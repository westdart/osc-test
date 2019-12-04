#
# Filter functions defining naming standard for AMQ and Interconnect instances
#
import re

def app_common_name(amq_ic_instance):
    return amq_ic_instance['name'].lower()

def app_namespace(amq_ic_instance, deployment_phase):
    if 'namespace' in amq_ic_instance:
        return amq_ic_instance['namespace'].lower()

    name = app_common_name(amq_ic_instance)
    phase = deployment_phase.lower()
    if 'parent' in amq_ic_instance:
        return amq_ic_instance['parent'].lower() + "-" + phase
    return name + "-" + phase

def internal_ic_host(amq_ic_instance, deployment_phase):
    return ic_application_name(amq_ic_instance) + "." + app_namespace(amq_ic_instance, deployment_phase) + ".svc"

def external_ic_host(amq_ic_instance, deployment_phase, domain):
    local_domain = amq_ic_instance['amq_ic_domain'] if 'amq_ic_domain' in amq_ic_instance else domain
    return ic_application_name(amq_ic_instance) + "-" + app_namespace(amq_ic_instance, deployment_phase) + "." + local_domain

def ic_application_name(amq_ic_instance):
    if 'ic_application_name' in amq_ic_instance:
        return amq_ic_instance['ic_application_name'].lower()
    name = app_common_name(amq_ic_instance)
    return name + "-interconnect"

def broker_application_name(amq_ic_instance):
    name = app_common_name(amq_ic_instance)
    return name + "-broker"

def aspera_application_name(amq_ic_instance):
    name = app_common_name(amq_ic_instance)
    return name + "-aspera"

def cert_subject_string(format, amq_ic_instance, deployment_phase, cert_defaults):
    local_cert_country = amq_ic_instance['cert_country'] if 'cert_country' in amq_ic_instance else cert_defaults['cert_country']
    local_cert_state   = amq_ic_instance['cert_state'] if 'cert_state' in amq_ic_instance else cert_defaults['cert_state']
    local_cert_locale = amq_ic_instance['cert_locale'] if 'cert_locale' in amq_ic_instance else cert_defaults['cert_locale']
    local_cert_organisation = amq_ic_instance['cert_organisation'] if 'cert_organisation' in amq_ic_instance else cert_defaults['cert_organisation']
    local_cert_organisation_unit = amq_ic_instance['cert_organisation_unit'] if 'cert_organisation_unit' in amq_ic_instance else cert_defaults['cert_organisation_unit']
    return format % (local_cert_country, local_cert_state, local_cert_locale, local_cert_organisation, local_cert_organisation_unit, internal_ic_host(amq_ic_instance, deployment_phase))

def cert_subject(amq_ic_instance, deployment_phase, cert_defaults):
    return cert_subject_string('/C=%s/ST=%s/L=%s/O=%s/OU=%s/CN=%s', amq_ic_instance, deployment_phase, cert_defaults)

def cert_subject_x509(amq_ic_instance, deployment_phase, cert_defaults):
    return cert_subject_string('subject=C = %s, ST = %s, L = %s, O = %s, OU = %s, CN = %s', amq_ic_instance, deployment_phase, cert_defaults)

def cert_subject_differs(str_subj, amq_ic_instance, deployment_phase, cert_defaults):
    regex = cert_subject_string('.*C *= *%s[,/] *ST *= *%s[,/] *L *= *%s[,/] *O *= *%s[,/] *OU *= *%s[,/] *CN *= *%s', amq_ic_instance, deployment_phase, cert_defaults)
    return re.search(regex, str_subj) is None


def amq_queues(amq_ic_instances, common_queues = []):
    result = []
    for queue in common_queues:
        result.append(queue)

    for amq_ic_instance in amq_ic_instances:
        for entry in amq_ic_instance['incomingAddressList']:
            result.append(entry)
            result.append('safi.events.to.' + entry)

    return result

class FilterModule(object):
    '''
    custom jinja2 filters for working with collections
    '''

    def filters(self):
        return {
            'internal_ic_host': internal_ic_host,
            'external_ic_host': external_ic_host,
            'ic_application_name': ic_application_name,
            'broker_application_name': broker_application_name,
            'aspera_application_name': aspera_application_name,
            'cert_subject': cert_subject,
            'cert_subject_x509': cert_subject_x509,
            'app_namespace': app_namespace,
            'amq_queues': amq_queues,
            'app_common_name': app_common_name,
            'cert_subject_differs': cert_subject_differs
        }

'''
Testing
'''
import unittest


class TestSelectFromArrayOfDicts(unittest.TestCase):
    amq_ic_instance = {
        'name': "TRG001",
        'incomingAddressList': ['addr_TRG001_1', 'addr_TRG001_2', 'addr_TRG001_3']
      }
    amq_ic_instance_with_parent = {
        'name':   "TRG002",
        'parent': "TRG001",
        'cert_locale': 'Else',
        'amq_ic_domain': 'test.com',
        'incomingAddressList': ['addr_TRG002_1', 'addr_TRG002_2', 'addr_TRG002_3']
    }

    amq_ic_instance_with_namespace = {
        'name':   "TRG003",
        'namespace': "my-NameSpace",
        'cert_locale': 'Else',
        'amq_ic_domain': 'test.com',
        'incomingAddressList': ['addr_TRG003_1', 'addr_TRG003_2', 'addr_TRG003_3']
    }

    amq_ic_instance_with_ic_application_name = {
        'name':   "TRG003",
        'namespace': "my-NameSpace",
        'cert_locale': 'Else',
        'amq_ic_domain': 'test.com',
        'incomingAddressList': ['addr_TRG003_1', 'addr_TRG003_2', 'addr_TRG003_3'],
        'ic_application_name': 'my-interconnect'
    }

    amq_ic_instances = [amq_ic_instance, amq_ic_instance_with_parent, amq_ic_instance_with_namespace]

    cert_defaults = {
        'cert_country': 'UK',
        'cert_state': 'Somewhere',
        'cert_locale': 'Near',
        'cert_organisation': 'By',
        'cert_organisation_unit': 'Here'
    }

    def test_internal_ic_host(self):
        result = internal_ic_host(self.amq_ic_instance, 'DEV')
        self.assertEqual('trg001-interconnect.trg001-dev.svc', result)

    def test_external_ic_host(self):
        result = external_ic_host(self.amq_ic_instance, 'DEV', 'domain')
        self.assertEqual('trg001-interconnect-trg001-dev.domain', result)

    def test_external_ic_host_with_parent(self):
        result = external_ic_host(self.amq_ic_instance_with_parent, 'DEV', 'test.com')
        self.assertEqual('trg002-interconnect-trg001-dev.test.com', result)

    def test_cert_subject(self):
        # C = UK, ST = Somewhere, O = By, OU = Here, CN = mesh-interconnect.dev-trg001.svc
        result = cert_subject(self.amq_ic_instance, 'DEV', self.cert_defaults)
        self.assertEqual('/C=UK/ST=Somewhere/L=Near/O=By/OU=Here/CN=trg001-interconnect.trg001-dev.svc', result)

    def test_cert_subject_x509(self):
        result = cert_subject_x509(self.amq_ic_instance, 'DEV', self.cert_defaults)
        self.assertEqual('subject=C = UK, ST = Somewhere, L = Near, O = By, OU = Here, CN = trg001-interconnect.trg001-dev.svc', result)

    def test_cert_subject_x509_override(self):
        result = cert_subject_x509(self.amq_ic_instance_with_parent, 'DEV', self.cert_defaults)
        self.assertEqual('subject=C = UK, ST = Somewhere, L = Else, O = By, OU = Here, CN = trg002-interconnect.trg001-dev.svc', result)

    def test_cert_subject_matches(self):
        self.assertFalse(cert_subject_differs('subject=C = UK, ST = Somewhere, L = Else, O = By, OU = Here, CN = trg002-interconnect.trg001-dev.svc', self.amq_ic_instance_with_parent, 'DEV', self.cert_defaults))

    def test_cert_subject_matches2(self):
        self.assertFalse(cert_subject_differs('/C=UK/ST=Somewhere/L=Else/O=By/OU=Here/CN=trg002-interconnect.trg001-dev.svc', self.amq_ic_instance_with_parent, 'DEV', self.cert_defaults))

    def test_cert_subject_not_matches(self):
        self.assertTrue(cert_subject_differs('subject=C = BG, ST = Somewhere, L = Else, O = By, OU = Here, CN = trg002-interconnect.trg001-dev.svc', self.amq_ic_instance_with_parent, 'DEV', self.cert_defaults))

    def test_external_ic_host_with_namespace(self):
        result = external_ic_host(self.amq_ic_instance_with_namespace, 'DEV', 'domain')
        self.assertEqual('trg003-interconnect-my-namespace.test.com', result)

    def test_external_ic_host_with_ic_application_name(self):
        result = external_ic_host(self.amq_ic_instance_with_ic_application_name, 'DEV', 'domain')
        self.assertEqual('my-interconnect-my-namespace.test.com', result)

    def test_queues(self):
        result = amq_queues(self.amq_ic_instances)
        self.assertEqual(18, len(result))

    def test_queues(self):
        result = amq_queues(self.amq_ic_instances, ['c1', 'c2'])
        self.assertEqual(20, len(result))

if __name__ == '__main__':
    unittest.main()
