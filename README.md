Here’s a clean **README.md** you can drop into your `db-setup-scripts` repo. It documents your current MySQL script and leaves placeholders for PostgreSQL and MSSQL so you can extend it later.

````markdown
# db-setup-scripts

Scripts for bootstrapping and managing development databases.  
Currently supports **MySQL**, with placeholders for **PostgreSQL** and **Microsoft SQL Server (MSSQL)**.

---

## 🚀 Features
- Interactive MySQL database and user creation
- Optional test database (`<dbname>_test`)
- Uses existing MySQL users or creates new ones
- Grants privileges automatically
- Supports **socket authentication** when run as `sudo` (no root password required on systems with `auth_socket` enabled)

---

## 📦 Requirements
- **MySQL client** (`mysql`) installed  
  ```bash
  sudo apt install mysql-client   # Debian/Ubuntu
  sudo yum install mysql          # CentOS/RHEL/Fedora
````

* A local or remote MySQL server accessible with admin privileges

---

## 📝 Usage

Clone the repo and run the script:

```bash
git clone https://github.com/YOUR-USERNAME/db-setup-scripts.git
cd db-setup-scripts
chmod +x mysql_setup.sh
./mysql_setup.sh
```

### With `sudo`

On systems where MySQL root uses `auth_socket`, you can run:

```bash
sudo ./mysql_setup.sh
```

This will attempt to connect as root **without a password**. If that fails, the script will prompt you for credentials.

---

## ⚙️ Script Flow

1. Connect to MySQL as root/admin
2. Prompt for new database name
3. Optionally create a `<dbname>_test` database
4. Select an existing MySQL user or create a new one
5. Create databases and grant privileges
6. Print summary

---

## 📂 Project Structure

```
db-setup-scripts/
├── mysql_setup.sh   # MySQL setup script
└── README.md        # Documentation
```

---

## 🗄️ Planned Support

### PostgreSQL (placeholder 🚧)

A future script will handle:

* Creating databases and roles
* Assigning privileges
* Optional test database setup
* Socket vs password authentication

> 📌 File to be added: `postgres_setup.sh`

---

### MSSQL (placeholder 🚧)

A future script will handle:

* Creating databases and logins
* Assigning users to databases
* Optional test database setup
* Windows/Linux authentication modes

> 📌 File to be added: `mssql_setup.sh`

---

## 🤝 Contributing

Feel free to open issues or submit PRs if you want to extend functionality for PostgreSQL, MSSQL, or add automation features (non-interactive mode, CI/CD integration, etc.).

---

