#!/bin/bash

# Ask for MySQL root credentials
read -p "MySQL root username [default: root]: " ROOT_USER
ROOT_USER=${ROOT_USER:-root}
read -s -p "MySQL root password: " ROOT_PASSWORD
echo ""

# Connect check
echo "Connecting to MySQL as $ROOT_USER..."
mysql -u"$ROOT_USER" -p"$ROOT_PASSWORD" -e "SELECT VERSION();" >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "❌ Connection failed. Please check credentials."
  exit 1
fi
echo "✅ Connected!"

# Step 1: Database name
read -p "Enter the new database name: " DB_NAME

# Step 2: Test DB
read -p "Do you want to create a test database (${DB_NAME}_test)? (y/n): " HAS_TEST
DB_TEST_NAME="${DB_NAME}_test"

# Step 3: Existing users
echo "Fetching existing MySQL users..."
EXISTING_USERS=$(mysql -u"$ROOT_USER" -p"$ROOT_PASSWORD" -e "SELECT User FROM mysql.user WHERE Host = 'localhost';" -s --skip-column-names)

echo "Available users:"
select USER_CHOICE in $EXISTING_USERS "Create new user"; do
  if [ "$USER_CHOICE" == "Create new user" ]; then
    read -p "Enter new username: " NEW_USER
    read -s -p "Enter password for new user: " NEW_PASS
    echo ""
    mysql -u"$ROOT_USER" -p"$ROOT_PASSWORD" -e "CREATE USER '$NEW_USER'@'localhost' IDENTIFIED BY '$NEW_PASS';"
    DB_USER=$NEW_USER
    break
  elif [[ -n "$USER_CHOICE" ]]; then
    DB_USER=$USER_CHOICE
    break
  else
    echo "❌ Invalid choice. Try again."
  fi
done

# Step 4: Create databases
mysql -u"$ROOT_USER" -p"$ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;"
mysql -u"$ROOT_USER" -p"$ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"

if [[ "$HAS_TEST" =~ ^[Yy]$ ]]; then
  mysql -u"$ROOT_USER" -p"$ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`$DB_TEST_NAME\`;"
  mysql -u"$ROOT_USER" -p"$ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON \`$DB_TEST_NAME\`.* TO '$DB_USER'@'localhost';"
fi

echo "🎉 Done! Databases and user setup:"
echo "  ➤ Main DB: $DB_NAME"
[[ "$HAS_TEST" =~ ^[Yy]$ ]] && echo "  ➤ Test DB: $DB_TEST_NAME"
echo "  ➤ DB User: $DB_USER"

