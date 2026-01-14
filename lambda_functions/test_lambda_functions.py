import json
import os
import importlib
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest


# ---------------------------------------------------------------------
# 0) Set env vars needed by BOTH modules *before import*
# ---------------------------------------------------------------------

# Region needed to build boto3 clients
os.environ.setdefault("AWS_DEFAULT_REGION", "eu-west-2")
os.environ.setdefault("AWS_REGION", "eu-west-2")

# Validation lambda env vars (read at import time)
os.environ.setdefault("PASS_BUCKET", "pass-bucket")
os.environ.setdefault("FAIL_BUCKET", "fail-bucket")
os.environ.setdefault("METADATA_BUCKET", "meta-bucket")
os.environ.setdefault("METADATA_PATH", "metadata/")
os.environ.setdefault("OUTPUT_KEY_PREFIX", "out-prefix")
os.environ.setdefault("OUTPUT_KEY_SUFFIX", "_suffix")
os.environ.setdefault("VALID_FILES_MUTABLE", "false")
os.environ.setdefault("SLACK_SECRET_ARN", "arn:slack-secret")

# Metadata generator env vars (safe defaults)
os.environ.setdefault("DMS_MAPPING_RULES_BUCKET", "rules-bucket")
os.environ.setdefault("DMS_MAPPING_RULES_KEY", "rules.json")
os.environ.setdefault("DB_SECRET_ARN", "arn:db-secret")
os.environ.setdefault("USE_GLUE_CATALOG", "true")
os.environ.setdefault("RAW_HISTORY_BUCKET", "raw-bucket")
os.environ.setdefault(
    "OUTPUT_KEY_PREFIX", "prefix"
)  # used by metadata_generator handler
os.environ.setdefault("INVALID_BUCKET", "invalid-bucket")
os.environ.setdefault("LANDING_BUCKET", "landing-bucket")
os.environ.setdefault("RETRY_FAILED_AFTER_RECREATE_METADATA", "false")
os.environ.setdefault("GLUE_CATALOG_ARN", "")


# ---------------------------------------------------------------------
# 1) Import modules under test
# ---------------------------------------------------------------------
metadata_mod = importlib.import_module("lambda_functions.metadata_generator.main")
validation_mod = importlib.import_module("lambda_functions.validation.main")


# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------


class FakePaginator:
    def __init__(self, pages):
        self._pages = pages

    def paginate(self, **kwargs):
        return iter(self._pages)


class FakeTable:
    def __init__(self, name: str):
        self.name = name


def _glue_with_entity_not_found():
    glue = MagicMock()

    class EntityNotFoundException(Exception):
        pass

    glue.exceptions.EntityNotFoundException = EntityNotFoundException
    return glue


@pytest.fixture
def secret_payload():
    return {
        "dbInstanceIdentifier": "mydbid",
        "username": "user",
        "oracle_password": "pass",
        "engine": "oracle",
        "host": "db.example",
        "dbname": "ORCL",
    }


@pytest.fixture
def mapping_rules():
    return {"objects": ["T1", "T2"], "schema": "myschema"}


# =====================================================================
# METADATA GENERATOR tests
# =====================================================================


def test_get_glue_client_without_role(monkeypatch):
    monkeypatch.delenv("GLUE_CATALOG_ROLE_ARN", raising=False)

    def fake_client(service, **kwargs):
        if service == "glue":
            assert kwargs == {}
            glue = MagicMock()
            glue.meta.region_name = "eu-west-2"
            return glue
        if service == "sts":
            raise AssertionError("STS should not be called when role arn not set")
        raise ValueError(service)

    monkeypatch.setattr(metadata_mod.boto3, "client", fake_client)

    client = metadata_mod._get_glue_client()
    assert client is not None
    assert client.meta.region_name == "eu-west-2"


@patch.object(metadata_mod, "reprocess_failed_records")
@patch.object(metadata_mod, "GlueConverter")
@patch.object(metadata_mod, "MetadataExtractor")
@patch.object(metadata_mod, "create_engine")
@patch.object(metadata_mod, "_get_glue_client")
@patch.object(metadata_mod, "_get_s3")
@patch.object(metadata_mod, "_get_secretmanager")
def test_metadata_handler_creates_db_and_tables_and_writes_s3(
    get_secretmanager,
    get_s3,
    get_glue_client,
    create_engine,
    MetadataExtractor,
    GlueConverter,
    reprocess_failed_records,
    secret_payload,
    mapping_rules,
    monkeypatch,
):
    # Ensure handler sees the intended module globals
    monkeypatch.setattr(metadata_mod, "db_secret_arn", "arn:db-secret")
    monkeypatch.setattr(metadata_mod, "dms_mapping_rules_bucket", "rules-bucket")
    monkeypatch.setattr(metadata_mod, "dms_mapping_rules_key", "rules.json")
    monkeypatch.setattr(metadata_mod, "metadata_bucket", "meta-bucket")
    monkeypatch.setattr(metadata_mod, "raw_history_bucket", "raw-bucket")
    monkeypatch.setattr(metadata_mod, "output_key_prefix", "prefix")
    monkeypatch.setattr(metadata_mod, "use_glue_catalog", True)
    monkeypatch.setattr(metadata_mod, "glue_catalog_arn", "")
    monkeypatch.setattr(metadata_mod, "retry_failed_after_recreate_metadata", True)

    # secretsmanager
    sm = MagicMock()
    sm.get_secret_value.return_value = {"SecretString": json.dumps(secret_payload)}
    get_secretmanager.return_value = sm

    # s3 mapping rules + output writes
    s3 = MagicMock()
    s3.get_object.return_value = {
        "Body": SimpleNamespace(
            readlines=lambda: [json.dumps(mapping_rules).encode("utf-8")]
        )
    }
    get_s3.return_value = s3

    # glue: db + tables missing
    glue = _glue_with_entity_not_found()
    glue.get_database.side_effect = glue.exceptions.EntityNotFoundException()
    glue.get_table.side_effect = glue.exceptions.EntityNotFoundException()
    get_glue_client.return_value = glue

    # sqlalchemy engine
    engine = MagicMock(name="engine")
    create_engine.return_value = engine

    # metadata extractor
    extractor = MagicMock()
    tables = [FakeTable("T1"), FakeTable("T2")]
    extractor.get_database_metadata.return_value = tables
    extractor.convert_metadata.side_effect = lambda t: f'{{"name":"{t.name}"}}'
    MetadataExtractor.return_value = extractor

    # glue converter → definitions
    gc = MagicMock()
    gc.generate_from_meta.side_effect = lambda table, dbid, loc: {
        "TableInput": {
            "Name": table.name.upper(),
            "Parameters": {"primary_key": "['ID']"},
        }
    }
    GlueConverter.return_value = gc

    metadata_mod.handler({}, SimpleNamespace())

    glue.create_database.assert_called_once()
    assert glue.create_table.call_count == 2
    assert s3.put_object.call_count == 2
    reprocess_failed_records.assert_called_once()


# =====================================================================
# VALIDATION tests
# =====================================================================


def test_validation_strip_data_type_valid():
    assert validation_mod.strip_data_type("decimal128(38,0)") == "decimal"
    assert validation_mod.strip_data_type("timestamp(s)") == "timestamp"
    assert validation_mod.strip_data_type("character") == "character"


def test_validation_strip_data_type_invalid_raises():
    with pytest.raises(validation_mod.MetadataTypeMismatchException):
        validation_mod.strip_data_type("not-a-type(1)")


def test_validation_return_agnostic_type_maps():
    assert validation_mod.return_agnostic_type("string") == "character"
    assert validation_mod.return_agnostic_type("int64", column_name="id") == "decimal"


def test_validation_handler_builds_metadata_keys_and_executes(monkeypatch):
    # Patch global s3 client in validation module
    s3_client = MagicMock()
    s3_client.get_paginator.return_value = FakePaginator(
        pages=[
            {
                "Contents": [
                    {"Key": "metadata/table1.json"},
                    {"Key": "metadata/table2.json"},
                ]
            }
        ]
    )
    monkeypatch.setattr(validation_mod, "client", s3_client)

    fv_instance = MagicMock()
    FileValidator_cls = MagicMock(return_value=fv_instance)
    monkeypatch.setattr(validation_mod, "FileValidator", FileValidator_cls)

    event = {
        "Records": [
            {
                "s3": {
                    "bucket": {"name": "source-bucket"},
                    "object": {"key": "raw/myschema/table1/file.parquet"},
                }
            }
        ]
    }

    validation_mod.handler(event, SimpleNamespace())

    kwargs = FileValidator_cls.call_args.kwargs
    assert kwargs["bucket_from"] == "source-bucket"
    assert kwargs["key"] == "raw/myschema/table1/file.parquet"
    assert kwargs["parquet_table_name"] == "table1"
    assert kwargs["metadata_s3_keys"] == {
        "table1": "metadata/table1.json",
        "table2": "metadata/table2.json",
    }
    fv_instance.execute.assert_called_once()
