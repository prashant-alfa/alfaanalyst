from app.data_sources.clients.base import DataSourceClient

import pandas as pd
import sqlalchemy
from sqlalchemy import text
from contextlib import contextmanager
from typing import List, Generator
from app.ai.prompt_formatters import Table, TableColumn
from app.ai.prompt_formatters import TableFormatter
from functools import cached_property
from urllib.parse import quote_plus


class MariadbClient(DataSourceClient):
    # [FIX 1] Updated __init__ to accept 'ssl'
    def __init__(self, host, port, database, user, password, ssl=False):
        self.host = host
        self.port = port
        self.database = database
        self.user = user
        self.password = password
        self.ssl = ssl

    @cached_property
    def mariadb_uri(self):
        auth_part = ""
        if self.user:
            auth_part = quote_plus(self.user)
            if self.password:
                auth_part += f":{quote_plus(self.password)}"
            auth_part += "@"
        
        uri = (
            f"mysql+pymysql://{auth_part}"
            f"{self.host}:{self.port}/{self.database}"
        )
        return uri

    @contextmanager
    def connect(self) -> Generator[sqlalchemy.engine.base.Connection, None, None]:
        """Yield a connection to a MariaDB database using pymysql."""
        engine = None
        conn = None
        try:
            # [FIX 2] Pass SSL args to engine
            connect_args = {}
            if self.ssl:
                connect_args["ssl"] = {"ssl_mode": "REQUIRED"}

            engine = sqlalchemy.create_engine(self.mariadb_uri, connect_args=connect_args)
            conn = engine.connect()

            yield conn
        except Exception as e:
            raise RuntimeError(f"Error while connecting to MariaDB: {e}")
        finally:
            if conn is not None:
                conn.close()
            if engine is not None:
                engine.dispose()

    # [FIX 3] Ensure cursor method is present (from previous fix)
    @contextmanager
    def cursor(self):
        """Yield a raw DB-API cursor."""
        with self.connect() as conn:
            raw_conn = conn.connection
            cursor = raw_conn.cursor()
            try:
                yield cursor
            finally:
                cursor.close()

    def execute_query(self, sql: str) -> pd.DataFrame:
        try:
            with self.connect() as conn:
                df = pd.read_sql(text(sql), conn)
            return df
        except Exception as e:
            print(f"Error executing SQL: {e}")
            raise

    def get_tables(self) -> List[Table]:
        try:
            with self.connect() as conn:
                sql = """
                    SELECT table_name, column_name, data_type
                    FROM information_schema.columns
                    WHERE table_schema = :database
                    ORDER BY table_name, ordinal_position
                """
                result = conn.execute(
                    text(sql), {'database': self.database}).fetchall()

                tables = {}
                for row in result:
                    table_name, column_name, data_type = row

                    if table_name not in tables:
                        tables[table_name] = Table(
                            name=table_name, columns=[], pks=[], fks=[])
                    tables[table_name].columns.append(
                        TableColumn(name=column_name, dtype=data_type))
                return list(tables.values())
        except Exception as e:
            print(f"Error retrieving tables: {e}")
            return []

    def get_schema(self, table_id: str) -> Table:
        raise NotImplementedError(
            "get_schema() is not implemented in MariadbClient. Use get_tables() instead.")

    def get_schemas(self):
        return self.get_tables()

    def prompt_schema(self):
        schemas = self.get_schemas()
        return TableFormatter(schemas).table_str

    def test_connection(self):
        try:
            with self.connect() as conn:
                conn.execute(text("SELECT 1"))
                return {
                    "success": True,
                    "message": "Successfully connected to MariaDB using pymysql"
                }
        except Exception as e:
            return {
                "success": False,
                "message": str(e)
            }

    @property
    def description(self):
        return f"MariaDB client (using pymysql) for database '{self.database}' at {self.host}:{self.port}"