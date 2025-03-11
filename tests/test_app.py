import unittest
from app import app  # adjust this import to match your application structure

class BasicTests(unittest.TestCase):
    def setUp(self):
        self.app = app.test_client()
        self.app.testing = True

    def test_home(self):
        response = self.app.get('/')
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Hello", response.data)

if __name__ == "__main__":
    unittest.main()
