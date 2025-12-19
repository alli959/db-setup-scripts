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

# -----------------------------
# Host & port selection
# -----------------------------
read -p "MySQL host [default: localhost]: " INPUT_HOST
MYSQL_HOST="${INPUT_HOST:-localhost}"

read -p "MySQL port [default: 3306]: " INPUT_PORT
MYSQL_PORT="${INPUT_PORT:-3306}"

MYSQL_CONN_OPTS+=( -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" )

# -----------------------------
# Socket auth (only localhost + default port)
# -----------------------------
if [[ "${EUID}" -eq 0 && "${MYSQL_HOST}" == "localhost" && "${MYSQL_PORT}" == "3306" ]]; then
  echo "🔐 Running as root: attempting socket auth as 'root'..."
  if "${MYSQL_BIN}" -u"${ROOT_USER}" -e "SELECT VERSION();" >/dev/null 2>&1; then
    AUTH_MODE="socket"
    MYSQL_CONN_OPTS+=( -u"${ROOT_USER}" )
    echo "✅ Connected via socket as ${ROOT_USER}"
  else
    echo "⚠️  Socket auth failed. Falling back to password prompt."
  fi
fi

# -----------------------------
# Password auth
# -----------------------------
if [[ "${AUTH_MODE}" != "socket" ]]; then
  read -p "MySQL admin username [default: root]: " INPUT_USER
  ROOT_USER=${INPUT_USER:-root}

  read -s -p "MySQL admin password: " ROOT_PASSWORD
  echo ""

  MYSQL_CONN_OPTS+=( -u"${ROOT_USER}" -p"${ROOT_PASSWORD}" )

  echo "Connecting to MySQL at ${MYSQL_HOST}:${MYSQL_PORT} as ${ROOT_USER}..."
  if ! "${MYSQL_BIN}" "${MYSQL_CONN_OPTS[@]}" -e "SELECT VERSION();" >/dev/null 2>&1; then
    echo "❌ Connection failed. Please check credentials."
    exit 1
  fi
  echo "✅ Connected!"
fi

# -----------------------------
# Helper to run SQL (supports extra mysql flags)
# -----------------------------
run_sql() {
  local sql="$1"
  shift
  "${MYSQL_BIN}" "${MYSQL_CONN_OPTS[@]}" "$@" -e "$sql"
}

# -----------------------------
# Detect how the server sees our client host
# -----------------------------
CLIENT_HOST="$(run_sql "SELECT SUBSTRING_INDEX(USER(),'@',-1);" -s --skip-column-names 2>/dev/null | tr -d '[:space:]' || true)"
if [[ -z "${CLIENT_HOST}" ]]; then
  CLIENT_HOST="${MYSQL_HOST}"
fi

if [[ "${CLIENT_HOST}" != "${MYSQL_HOST}" ]]; then
  echo "ℹ️  Note: you connected to ${MYSQL_HOST}, but the server sees your client as '${CLIENT_HOST}'."
  echo "   (This is common with Docker port-mapping / NAT and affects 'user'@'host' matching.)"
fi

# -----------------------------
# Database setup
# -----------------------------
read -p "Enter the new database name: " DB_NAME
if [[ -z "${DB_NAME}" ]]; then
  echo "❌ Database name is required."
  exit 1
fi

read -p "Do you want to create a test database (${DB_NAME}_test)? (y/n): " HAS_TEST
DB_TEST_NAME="${DB_NAME}_test"

# -----------------------------
# Existing users (show user@host)
# -----------------------------
echo "Fetching existing MySQL users..."
EXISTING_USERS=$(run_sql \
  "SELECT CONCAT(User,'@',Host) FROM mysql.user ORDER BY User, Host;" \
  -s --skip-column-names 2>/dev/null | tr '\n' ' ')

if [[ -z "${EXISTING_USERS}" ]]; then
  echo "⚠️  No existing users found in mysql.user."
fi

echo "Available users:"
echo "  (Tip: For your current connection, prefer a user whose host is '${CLIENT_HOST}' or '%' )"

select USER_CHOICE in $EXISTING_USERS "Create new user"; do
  if [[ "$USER_CHOICE" == "Create new user" ]]; then
    read -p "Enter new username: " NEW_USER

    echo "Host for this user determines where it can connect FROM."
    echo "  - Default is what the server sees your connection as: ${CLIENT_HOST}"
    echo "  - Use '%' to allow from anywhere (common for Docker/remote apps)"
    read -p "Host for this user [default: ${CLIENT_HOST}]: " INPUT_UHOST
    USER_HOST="${INPUT_UHOST:-${CLIENT_HOST}}"

    read -s -p "Enter password for new user: " NEW_PASS
    echo ""

    run_sql "CREATE USER IF NOT EXISTS '${NEW_USER}'@'${USER_HOST}' IDENTIFIED BY '${NEW_PASS}';"
    DB_USER="${NEW_USER}"
    DB_USER_HOST="${USER_HOST}"
    break

  elif [[ -n "$USER_CHOICE" ]]; then
    DB_USER="${USER_CHOICE%@*}"
    DB_USER_HOST="${USER_CHOICE#*@}"

    # If you selected a host that won't match your current connection, offer to fix it.
    if [[ "${DB_USER_HOST}" != "%" && "${DB_USER_HOST}" != "${CLIENT_HOST}" ]]; then
      echo ""
      echo "⚠️  You selected '${DB_USER}@${DB_USER_HOST}', but the server sees your client host as '${CLIENT_HOST}'."
      echo "    This will likely FAIL when you try to connect as '${DB_USER}' (exactly like your error)."
      echo ""
      echo "Choose how to fix it:"
      echo "  1) Use '${DB_USER}@${CLIENT_HOST}' (best for this exact setup)"
      echo "  2) Use '${DB_USER}@%' (works across Docker/hosts; broader access)"
      echo "  3) Keep '${DB_USER}@${DB_USER_HOST}' anyway"
      read -p "Select [1/2/3] (default: 1): " FIX_CHOICE
      FIX_CHOICE="${FIX_CHOICE:-1}"

      case "${FIX_CHOICE}" in
        1)
          DB_USER_HOST="${CLIENT_HOST}"
          echo "✅ Will use: ${DB_USER}@${DB_USER_HOST}"
          ;;
        2)
          DB_USER_HOST="%"
          echo "✅ Will use: ${DB_USER}@${DB_USER_HOST}"
          ;;
        3)
          echo "⚠️  Keeping: ${DB_USER}@${DB_USER_HOST} (may not work for TCP/Docker NAT)"
          ;;
        *)
          DB_USER_HOST="${CLIENT_HOST}"
          echo "✅ Will use: ${DB_user}@${DB_USER_HOST}"
          ;;
      esac

      # If the chosen fixed host user doesn't exist yet, ask for password and create it.
      EXISTS="$(run_sql \
        "SELECT COUNT(*) FROM mysql.user WHERE User='${DB_USER}' AND Host='${DB_USER_HOST}';" \
        -s --skip-column-names 2>/dev/null | tr -d '[:space:]' || echo "0")"

      if [[ "${EXISTS}" == "0" ]]; then
        echo ""
        echo "ℹ️  Account '${DB_USER}'@'${DB_USER_HOST}' does not exist yet. Creating it now."
        read -s -p "Enter password for ${DB_USER}@${DB_USER_HOST}: " NEW_PASS
        echo ""
        run_sql "CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_USER_HOST}' IDENTIFIED BY '${NEW_PASS}';"
      fi
    fi

    break
  else
    echo "❌ Invalid choice. Try again."
  fi
done

# -----------------------------
# Create databases & grants
# -----------------------------
run_sql "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;"
run_sql "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${DB_USER_HOST}';"

if [[ "$HAS_TEST" =~ ^[Yy]$ ]]; then
  run_sql "CREATE DATABASE IF NOT EXISTS \`${DB_TEST_NAME}\`;"
  run_sql "GRANT ALL PRIVILEGES ON \`${DB_TEST_NAME}\`.* TO '${DB_USER}'@'${DB_USER_HOST}';"
fi

run_sql "FLUSH PRIVILEGES;"

# -----------------------------
# Summary
# -----------------------------
echo "🎉 Done! Databases and user setup:"
echo "  ➤ Connected to: ${MYSQL_HOST}:${MYSQL_PORT}"
echo "  ➤ Server sees client as: ${CLIENT_HOST}"
echo "  ➤ Main DB: ${DB_NAME}"
[[ "$HAS_TEST" =~ ^[Yy]$ ]] && echo "  ➤ Test DB: ${DB_TEST_NAME}"
echo "  ➤ DB User: ${DB_USER}@${DB_USER_HOST}"

