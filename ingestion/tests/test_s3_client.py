import boto3
import pytest
from ingest_trip_data import ALREADY_INGESTED_EXIT_CODE, run
from moto import mock_aws
from s3_client import month_already_ingested, upload_month_file


@pytest.fixture
def s3_bucket():
    """Creates a fake S3 bucket in moto's simulated AWS, for the
    duration of one test."""
    with mock_aws():
        client = boto3.client("s3", region_name="us-west-2")
        client.create_bucket(
            Bucket="test-bucket",
            CreateBucketConfiguration={"LocationConstraint": "us-west-2"},
        )
        yield client


def test_month_already_ingested_returns_false_when_nothing_exists(s3_bucket):
    result = month_already_ingested(s3_bucket, "test-bucket", 2024, 1)
    assert result is False


def test_month_already_ingested_returns_true_when_file_exists(s3_bucket):
    s3_bucket.put_object(
        Bucket="test-bucket",
        Key="raw/yellow_tripdata/2024/01/yellow_tripdata_2024-01.parquet",
        Body=b"fake parquet content",
    )
    result = month_already_ingested(s3_bucket, "test-bucket", 2024, 1)
    assert result is True

def test_upload_then_check_idempotency_are_consistent(s3_bucket):
    """Regression test: upload_month_file and month_already_ingested must
    agree on the same partition path. A typo in either function's key-building
    logic would cause this test to fail, even though each function might
    individually 'work' in isolation."""
    fake_stream = __import__("io").BytesIO(b"fake parquet content")

    final_key = upload_month_file(s3_bucket, "test-bucket", fake_stream, 2024, 6)

    assert month_already_ingested(s3_bucket, "test-bucket", 2024, 6) is True
    assert "yellow_tripdata" in final_key
    assert "2024" in final_key and "06" in final_key

class FakeResponse:
    def __init__(self, status_code, content=b"fake parquet data"):
        self.status_code = status_code
        self.raw = __import__("io").BytesIO(content)

    def raise_for_status(self):
        if self.status_code >= 400:
            import requests
            raise requests.exceptions.HTTPError(f"{self.status_code} error")


def test_run_ingests_new_month(s3_bucket, monkeypatch):
    monkeypatch.setattr(
        "ingest_trip_data.RAW_BUCKET", "test-bucket"
    )
    monkeypatch.setattr(
        "ingest_trip_data.requests.get",
        lambda *args, **kwargs: FakeResponse(200),
    )
    monkeypatch.setattr(
        "ingest_trip_data.get_s3_client",
        lambda profile_name, region: s3_bucket,
    )

    was_ingested = run(2024, 6)

    assert was_ingested is True

    

def test_run_skips_already_ingested_month(s3_bucket, monkeypatch):
    # Pre-populate the fake bucket with the file already "ingested"
    s3_bucket.put_object(
        Bucket="test-bucket",
        Key="raw/yellow_tripdata/2024/06/yellow_tripdata_2024-06.parquet",
        Body=b"already here",
    )

    monkeypatch.setattr("ingest_trip_data.RAW_BUCKET", "test-bucket")
    monkeypatch.setattr(
        "ingest_trip_data.get_s3_client",
        lambda profile_name, region: s3_bucket,
    )

    def fail_if_called(*args, **kwargs):
        raise AssertionError("requests.get should never be called for an already-ingested month")

    monkeypatch.setattr("ingest_trip_data.requests.get", fail_if_called)

    was_ingested = run(2024, 6)

    assert was_ingested is False