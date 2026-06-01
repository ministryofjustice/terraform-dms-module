# Utility Lambda for executing SQL against Oracle RDS in private subnets.
# Use this when no EC2 bastion/jump host is available for direct bash connectivity.
import json
from typing import Any

import oracledb


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Execute SQL statements against Oracle RDS.

    Event format:
    {
        "host": "rds-endpoint",
        "port": 1521,
        "user": "admin",
        "password": "...",
        "service_name": "DMSTEST",
        "sql_statements": ["SELECT 1 FROM DUAL", "..."]
    }
    """
    host = event["host"]
    port = event.get("port", 1521)
    user = event["user"]
    password = event["password"]
    service_name = event["service_name"]
    statements = event["sql_statements"]

    dsn = f"{host}:{port}/{service_name}"
    results = []

    try:
        with oracledb.connect(user=user, password=password, dsn=dsn) as conn:
            for sql in statements:
                sql_stripped = sql.strip()
                # Only strip trailing semicolons from plain SQL, not PL/SQL blocks
                if not sql_stripped.upper().startswith(
                    "BEGIN"
                ) and not sql_stripped.upper().startswith("DECLARE"):
                    sql_stripped = sql_stripped.rstrip(";")
                try:
                    with conn.cursor() as cursor:
                        cursor.execute(sql_stripped)
                        if cursor.description:
                            columns = [col[0] for col in cursor.description]
                            rows = [
                                dict(zip(columns, row)) for row in cursor.fetchmany(100)
                            ]
                            results.append(
                                {
                                    "sql": sql,
                                    "status": "ok",
                                    "columns": columns,
                                    "rows": rows,
                                }
                            )
                        else:
                            conn.commit()
                            results.append(
                                {
                                    "sql": sql,
                                    "status": "ok",
                                    "rowcount": cursor.rowcount,
                                }
                            )
                except Exception as e:
                    results.append({"sql": sql, "status": "error", "error": str(e)})
    except Exception as e:
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}

    return {"statusCode": 200, "body": json.dumps(results, default=str)}
