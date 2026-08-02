import os

AWS_PROFILE = os.environ.get("AWS_PROFILE", "nyc-taxi-ingestion-user")
AWS_REGION = os.environ.get("AWS_REGION", "us-west-2")
RAW_BUCKET = os.environ.get("RAW_BUCKET_NAME", "nyc-taxi-raw-ds-dmitry-dev")

SOURCE_BASE_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data"
