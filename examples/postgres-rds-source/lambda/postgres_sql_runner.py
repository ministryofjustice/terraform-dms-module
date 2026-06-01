# Utility Lambda for executing SQL against Postgres RDS in private subnets.
# Use only for throwaway/test environments where no EC2 bastion/jump host is
# available. This Lambda accepts arbitrary SQL and database credentials in the
# invocation payload, so invoke permissions must be tightly restricted and it
# must not be deployed for production/shared databases.

import json
from typing import Any

import psycopg


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Execute SQL statements against Postgres RDS.

    Event format:
    {
        "host": "rds-endpoint",
        "port": 5432,
        "user": "admin",
        "password": "...",
        "dbname": "dmstest",
        "sql_statements": ["SELECT 1", "..."]
    }
    """
    host = event["host"]
    port = event.get("port", 5432)
    user = event["user"]
    password = event["password"]
    dbname = event.get("dbname", "dmstest")
    statements = event["sql_statements"]

    results = []

    try:
        with psycopg.connect(
            host=host,
            port=port,
            user=user,
            password=password,
            dbname=dbname,
        ) as conn:
            for sql in statements:
                sql_stripped = sql.strip()

                try:
                    with conn.cursor() as cursor:
                        cursor.execute(sql_stripped)

                        if cursor.description:
                            columns = [col.name for col in cursor.description]
                            rows = [
                                dict(zip(columns, row))
                                for row in cursor.fetchmany(100)
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
                            results.append(
                                {
                                    "sql": sql,
                                    "status": "ok",
                                    "rowcount": cursor.rowcount,
                                }
                            )

                    conn.commit()

                except Exception as e:
                    conn.rollback()
                    results.append(
                        {
                            "sql": sql,
                            "status": "error",
                            "error": str(e),
                        }
                    )

    except Exception as e:
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}

    return {"statusCode": 200, "body": json.dumps(results, default=str)}