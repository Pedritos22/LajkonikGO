import os
from pathlib import Path
import subprocess
import sys
import unittest


BACKEND_DIR = Path(__file__).resolve().parents[1]


class MigrationConfigTests(unittest.TestCase):
    def run_backend(self, *args, database_url=None):
        env = os.environ.copy()
        env.pop("DATABASE_URL", None)
        if database_url is not None:
            env["DATABASE_URL"] = database_url
        return subprocess.run(
            [sys.executable, *args],
            cwd=BACKEND_DIR,
            env=env,
            capture_output=True,
            text=True,
        )

    def test_database_import_with_default_configuration(self):
        result = self.run_backend("-c", "import app.database; import app.models")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_offline_migration_with_url_encoded_credentials(self):
        result = self.run_backend(
            "-m", "alembic", "upgrade", "head", "--sql",
            database_url="postgresql+psycopg://review:p%40ss%25word@localhost/review",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CREATE TABLE users", result.stdout)
        self.assertIn("COMMIT;", result.stdout)

if __name__ == "__main__":
    unittest.main()
