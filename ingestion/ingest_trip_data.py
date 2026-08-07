import argparse
import logging
import sys

import requests
from config import AWS_PROFILE, AWS_REGION, RAW_BUCKET, SOURCE_BASE_URL
from s3_client import get_s3_client, month_already_ingested, upload_month_file

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)

logger = logging.getLogger(__name__)

ALREADY_INGESTED_EXIT_CODE = 99

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Ingest NYC TLC Yellow taxi trip data into S3 raw zone"
    )
    parser.add_argument("--year", type=int, required=True)
    parser.add_argument("--month", type=int, required=True, choices=range(1, 13))
    return parser.parse_args()


def run(year: int, month: int) -> None:
    s3_client = get_s3_client(profile_name=AWS_PROFILE, region=AWS_REGION)

    if month_already_ingested(s3_client, RAW_BUCKET, year, month):
        logger.info("Month %s-%02d already ingested, skipping.", year, month)
        return False

    source_url = f"{SOURCE_BASE_URL}/yellow_tripdata_{year}-{month:02d}.parquet"
    logger.info("Downloading from %s", source_url)

    response = requests.get(source_url, stream=True, timeout=30)
    response.raise_for_status()

    final_key = upload_month_file(s3_client, RAW_BUCKET, response.raw, year, month)
    logger.info("Ingestion complete: s3://%s/%s", RAW_BUCKET, final_key)


if __name__ == "__main__":
    args = parse_args()
    try:
        was_ingested = run(args.year, args.month)
        if not was_ingested:
            sys.exit(ALREADY_INGESTED_EXIT_CODE)
    except Exception:
        logger.exception("Ingestion failed for %s-%02d", args.year, args.month)
        sys.exit(1)
