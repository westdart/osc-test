def merge_dicts(dict1, dict2):
    '''
    Args:
        dict1: First dict
        dict2: second dict
    Returns: dict object containing both sets of data
    '''
    result = dict1.copy()
    result.update(dict2)
    return result

def merge_list_of_dicts(list, dict):
    '''
    Args:
        dict1: First dict
        dict2: second dict
    Returns: dict object containing both sets of data
    '''
    result = []
    for entry in list:
        result.append(merge_dicts(entry, dict))
    return result


class FilterModule(object):
    '''
    custom jinja2 filters for working with collections
    '''

    def filters(self):
        return {
            'merge_dicts': merge_dicts,
            'merge_list_of_dicts': merge_list_of_dicts
        }


'''
Testing
'''
import unittest


class TestMergeDicts(unittest.TestCase):
    dict1 = {'name1': "one", 'value1': "one value"}
    dict2 = {'name2': "two", 'value2': "two value"}
    dict_list = [dict1, dict2]

    def test_merge_dicts(self):
        result = merge_dicts(self.dict1, self.dict2)

        self.assertEqual(4, len(result.keys()))
        self.assertEqual('one', result['name1'])
        self.assertEqual('two value', result['value2'])

    def test_merge_list_of_dicts(self):
        d = {'new_key': 'new_value'}
        result = merge_list_of_dicts(self.dict_list, d)

        self.assertEqual(2, len(result))
        self.assertEqual('new_value', result[0]['new_key'])
        self.assertEqual('new_value', result[1]['new_key'])
        self.assertEqual('one value', result[0]['value1'])
        self.assertEqual('two', result[1]['name2'])

