import unittest

from proto.py.mod import newer


class NewerTest(unittest.TestCase):
    def test_compares_versions_not_strings(self):
        self.assertTrue(newer("1.10", "1.9"))


if __name__ == "__main__":
    unittest.main()
