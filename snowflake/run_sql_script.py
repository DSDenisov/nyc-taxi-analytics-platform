import argparse
import logging
import os
from pathlib import Path

import snowflake.connector
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent / ".env")

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logging.getLogger("botocore").setLevel(logging.WARNING)
logging.getLogger("boto3").setLevel(logging.WARNING)
logger = logging.getLogger(__name__)


def get_connection():
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        role=os.environ["SNOWFLAKE_ROLE"],
        warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
        database=os.environ["SNOWFLAKE_DATABASE"],
        private_key_file=os.environ["LOADER_PRIVATE_KEY_PATH"],
    )


def run_sql_file(path: str) -> None:
    with open(path, "r") as f:
        sql_text = f.read()

    statements = [s.strip() for s in sql_text.split(";") if s.strip()]

    conn = get_connection()
    try:
        cursor = conn.cursor()
        for statement in statements:
            logger.info("Executing: %s", statement[:100])
            cursor.execute(statement)
    finally:
        conn.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run a .sql file against Snowflake")
    parser.add_argument("--file", required=True)
    args = parser.parse_args()
    run_sql_file(args.file)