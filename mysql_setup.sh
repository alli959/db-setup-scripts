#!/bin/bash
set -euo pipefail

# Pick the mysql client (works for MySQL and MariaDB)
MYSQL_BIN="$(command -v mysql || true)"
if [[ -z "${MYSQL_BIN}" ]]; then
  echo "❌ 'mysql' client not found. Install mysql-client or mariadb-client."
  exit 1
fi

MYSQL_CONN_OPTS=()
ROOT_USER="root"
AUTH_MODE="prompt"  # 'socket' when running as root and socket auth works

# If running with sudo/root, try socket auth (no password prompt)
if [[ "${EUID}" -eq 0 ]]; then
  echo "🔐 Running as root: attempting socket auth as 'root'..."
  if "${MYSQL_BIN}" -u"${ROOT_USER}" -e "SELECT VERSION();" >/dev/null 2>&1; then
    AUTH_MODE="socket"
    MYSQL_CONN_OPTS=( -u"${ROOT_USER}" )
    echo "✅ Connected via socket as ${ROOT_USER}"
  else
    echo "⚠️  Socket auth failed. Falling back to password prompt."
  fi
fi

# If socket auth didn’t work (non-root or disabled), prompt for creds
if [[ "${AUTH_MODE}" != "socket" ]]; then
  read -p "MySQL admin username [default: root]: " INPUT_USER
  ROOT_USER=${INPUT_USER:-root}
  read -s -p "MySQL admin password: " ROOT_PASSWORD
  echo ""
  MYSQL_CONN_OPTS=( -u"${ROOT_USER}" -p"${ROOT_PASSWORD}" )

  echo "Connecting to MySQL as ${ROOT_USER}..."
  if ! "${MYSQL_BIN}" "${MYSQL_CONN_OPTS[@]}" -e "SELECT VERSION();" >/dev/null 2>&1; then
    echo "❌ Connection failed. Please check credentials."
    exit 1
  fi
  echo "✅ Connected!"
fi

# Helper to run SQL
run_sql() {
  "${MYSQL_BIN}" "${MYSQL_CONN_OPTS[@]}" -e "$1"
}

# Step 1: Database name
read -p "Enter the new database name: " DB_NAME
if [[ -z "${DB_NAME}" ]]; then
  echo "❌ Database name is required."
  exit 1
fi

# Step 2: Test DB
read -p "Do you want to create a test database (${DB_NAME}_test)? (y/n): " HAS_TEST
DB_TEST_NAME="${DB_NAME}_test"

# Step 3: Existing users
echo "Fetching existing MySQL users..."
EXISTING_USERS=$(run_sql "SELECT User FROM mysql.user WHERE Host = 'localhost';" -s --skip-column-names 2>/dev/null | tr '\n' ' ')
if [[ -z "${EXISTING_USERS}" ]]; then
  echo "⚠️  No existing users found for Host='localhost'."
fi

echo "Available users:"
select USER_CHOICE in $EXISTING_USERS "Create new user"; do
  if [[ "$USER_CHOICE" == "Create new user" ]]; then
    read -p "Enter new username: " NEW_USER
    read -s -p "Enter password for new user: " NEW_PASS
    echo ""
    run_sql "CREATE USER IF NOT EXISTS '${NEW_USER}'@'localhost' IDENTIFIED BY '${NEW_PASS}';"
    DB_USER=$NEW_USER
    break
  elif [[ -n "$USER_CHOICE" ]]; then
    DB_USER=$USER_CHOICE
    break
  else
    echo "❌ Invalid choice. Try again."
  fi
done

# Step 4: Create databases and grant privileges
run_sql "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;"
run_sql "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"

if [[ "$HAS_TEST" =~ ^[Yy]$ ]]; then
  run_sql "CREATE DATABASE IF NOT EXISTS \`${DB_TEST_NAME}\`;"
  run_sql "GRANT ALL PRIVILEGES ON \`${DB_TEST_NAME}\`.* TO '${DB_USER}'@'localhost';"
fi

# Flush to ensure grants are applied immediately on older setups
run_sql "FLUSH PRIVILEGES;"

echo "🎉 Done! Databases and user setup:"
echo "  ➤ Main DB: ${DB_NAME}"
[[ "$HAS_TEST" =~ ^[Yy]$ ]] && echo "  ➤ Test DB: ${DB_TEST_NAME}"
echo "  ➤ DB User: ${DB_USER}"

