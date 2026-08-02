import logging
from uuid import uuid4

import boto3

logger = logging.getLogger(__name__)
DATASET_NAME = "yellow_tripdata"


def get_s3_client(profile_name: str, region: str):
    session = boto3.Session(profile_name=profile_name, region_name=region)
    return session.client("s3")


def _partition_prefix(year: int, month: int) -> str:
    return f"raw/{DATASET_NAME}/{year}/{month:02d}/"


def month_already_ingested(s3_client, bucket: str, year: int, month: int) -> bool:
    response = s3_client.list_objects_v2(
        Bucket=bucket, Prefix=_partition_prefix(year, month)
    )
    return response.get("KeyCount", 0) > 0


def upload_month_file(
    s3_client, bucket: str, source_stream, year: int, month: int
) -> str:
    final_key = (
        f"{_partition_prefix(year, month)}{DATASET_NAME}_{year}-{month:02d}.parquet"
    )
    temp_key = f"_tmp/{DATASET_NAME}_{year}-{month:02d}_{uuid4().hex}.parquet"

    logger.info("Uploading to temp key %s", temp_key)
    s3_client.upload_fileobj(source_stream, bucket, temp_key)

    logger.info("Copying temp key to final key: %s", final_key)
    s3_client.copy_object(
        Bucket=bucket, CopySource={"Bucket": bucket, "Key": temp_key}, Key=final_key
    )

    return final_key
