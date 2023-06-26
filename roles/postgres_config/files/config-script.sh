#!/bin/bash
echo "Configuring PostgreSQL"
echo "SELECT 'CREATE DATABASE $DB_NAME' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME')\gexec" | psql -d postgres -w
echo "SELECT 'CREATE USER $DB_USER' WHERE NOT EXISTS (SELECT FROM pg_user WHERE usename = '$DB_USER')\gexec" | psql -d postgres -w
echo "ALTER USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASS'" | psql -d postgres -w
echo "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME to $DB_USER" | psql -d postgres -w
echo "$DB_CUSTOM_COMMAND" | psql -d postgres -w