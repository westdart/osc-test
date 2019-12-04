def select_from_array_of_dicts(the_array, column_name, column_value):
    '''
    Args:
        the_array: Array of dict object
        column_name: name of column to search on
        column_value: value required for entry to make it into the output. This can either be a string or an array of
        strings
    Returns: Filtered list of dict objects
    '''
    result = []
    for entry in the_array:
        if column_name in entry:
            if isinstance(column_value, str):
                if entry[column_name] == column_value:
                    result.append(entry)
            elif isinstance(column_value, list):
                for val in column_value:
                    if entry[column_name] == val:
                        result.append(entry)
    return result


class FilterModule(object):
    '''
    custom jinja2 filters for working with collections
    '''

    def filters(self):
        return {
            'select_from_array_of_dicts': select_from_array_of_dicts
        }


'''
Testing
'''
import unittest


class TestSelectFromArrayOfDicts(unittest.TestCase):
    data = [
        {'name': "one", 'value': "one value"},
        {'name': "two", 'value': "one of two values"},
        {'name': "two", 'value': "two of two values"}
    ]

    def test_server_names_array(self):
        result = select_from_array_of_dicts(self.data, 'name', 'one')

        self.assertEqual(1, len(result))
        self.assertEqual("one value", result[0]['value'])

    def test_server_names_array_miss(self):
        result = select_from_array_of_dicts(self.data, 'name', 'three')

        self.assertEqual(0, len(result))

    def test_server_names_array_invalid(self):
        result = select_from_array_of_dicts(self.data, 'foo', 'one')

        self.assertEqual(0, len(result))

    def test_server_names_array_multi(self):
        result = select_from_array_of_dicts(self.data, 'name', 'two')

        self.assertEqual(2, len(result))
        self.assertEqual("one of two values", result[0]['value'])
        self.assertEqual("two of two values", result[1]['value'])

    def test_server_names_array_multi_vals(self):
        result = select_from_array_of_dicts(self.data, 'name', ['one', 'two'])

        self.assertEqual(3, len(result))
        self.assertEqual("one value", result[0]['value'])
        self.assertEqual("one of two values", result[1]['value'])
        self.assertEqual("two of two values", result[2]['value'])

    def test_server_names_array_no_vals(self):
        result = select_from_array_of_dicts(self.data, 'name', [])

        self.assertEqual(0, len(result))


if __name__ == '__main__':
    unittest.main()
