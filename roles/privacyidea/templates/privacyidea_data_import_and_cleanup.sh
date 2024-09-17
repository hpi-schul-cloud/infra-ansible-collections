#!/bin/bash
# Define the MySQL credentials and database

DB_USER="{{ mariadb_user }}"
DB_NAME="{{ privacyidea_mariadb_name }}"
DB_PASSWORD="{{ privacyidea_db_user_password }}"
DUMP_FILE="CRQ000002489570_dump.sql"

# Import the SQL dump
mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME < /var/backups/$DUMP_FILE
echo "SQL dump imported."

# Verify the token count
TOKEN_COUNT=$(mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME -sse "SELECT COUNT(*) FROM token;")
if [ "$TOKEN_COUNT" -ne 37985 ]; then
  echo "Error: Token count is $TOKEN_COUNT, but it should be 37985."
else
  echo "Token count is correct: $TOKEN_COUNT"
fi

# Remove existing admin users
mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "DELETE FROM admin;"
echo "Existing admin users deleted."

# Create new admin users
sudo -u www-data /opt/privacyidea/virtualenv/bin/pi-manage admin add admin --password "{{ privacyidea_admin_password }}"
sudo -u www-data /opt/privacyidea/virtualenv/bin/pi-manage admin add token-admin --password "{{ privacyidea_token_admin_password }}"
sudo -u www-data /opt/privacyidea/virtualenv/bin/pi-manage admin add seed-import --password "{{ privacyidea_seed_import_password }}"
echo "New admin users created."

# Drop & Recreate users_service table
mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "
  SET FOREIGN_KEY_CHECKS = 0;
  DROP TABLE IF EXISTS users_service;
  CREATE TABLE users_service (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(40) UNIQUE
  );
  INSERT INTO users_service (username)
  SELECT DISTINCT user_id COLLATE utf8mb4_general_ci
  FROM tokenowner
  WHERE user_id COLLATE utf8mb4_general_ci NOT IN (SELECT username FROM users_service);
  SET FOREIGN_KEY_CHECKS = 1;
"
echo "users_service table created."

# Remove existing resolverconfig
mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "
  SET FOREIGN_KEY_CHECKS = 0;
  DELETE FROM resolverconfig;
"
echo "Deleted ldap resolverconfig."

# update existing service sqlresolver:
sudo -u www-data /opt/privacyidea/virtualenv/bin/pi-manage resolver create service  sqlresolver /etc/privacyidea/user_sql_resolver_config.ini

# Create two new sqlresolvers
sudo -u www-data /opt/privacyidea/virtualenv/bin/pi-manage resolver create domain_admins sqlresolver /etc/privacyidea/admin_sql_resolver_config.ini
sudo -u www-data /opt/privacyidea/virtualenv/bin/pi-manage resolver create domain_users sqlresolver /etc/privacyidea/user_sql_resolver_config.ini
echo "Created domain_admins and domain_users sqlresolvers."


# Determine the resolver_id of the domain_admins and domain_users resolvers and store them in a variable
#Modify your SQL queries to  select just ID
RESOLVER_ID_DOMAIN_USERS=$(mysql -u $DB_USER -p$DB_PASSWORD -N -s -e "SELECT id FROM resolver WHERE name = 'domain_users';" $DB_NAME)
RESOLVER_ID_DOMAIN_ADMIN=$(mysql -u $DB_USER -p$DB_PASSWORD -N -s -e "SELECT id FROM resolver WHERE name = 'domain_admins';" $DB_NAME)

#return the new resolver_id
echo "The resolver ID for 'domain_users' is: $RESOLVER_ID_DOMAIN_USERS"
echo "The resolver ID for 'domain_admin' is: $RESOLVER_ID_DOMAIN_ADMIN"

# Remove ldap resolvers
mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "
  SET FOREIGN_KEY_CHECKS = 0;
  DELETE FROM resolver WHERE id IN (6);
  DELETE FROM resolver WHERE id IN (9);
"
echo "Deleted ldapresolvers."

#Update resolver IDs and names
mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "
     SET FOREIGN_KEY_CHECKS = 0;
     UPDATE resolver SET id = 6, name = 'ucs_users' WHERE name = 'domain_users';
     UPDATE resolver SET id = 9, name = 'ucs_domain_admins' WHERE name = 'domain_admins';
     UPDATE resolverconfig SET resolver_id = 6 WHERE resolver_id = $RESOLVER_ID_DOMAIN_USERS;
     UPDATE resolverconfig SET resolver_id = 9 WHERE resolver_id = $RESOLVER_ID_DOMAIN_ADMIN;
     SET FOREIGN_KEY_CHECKS = 1;
"
echo "Updated resolver IDs and names."

#Separate step to delete specific policy conditions
mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "
  SET FOREIGN_KEY_CHECKS = 0;
  DELETE FROM policycondition WHERE policy_id IN (SELECT id FROM policy WHERE name = 'no_student_token');
  DELETE FROM policy WHERE name = 'no_student_token';
  SET FOREIGN_KEY_CHECKS = 1;
"
echo "Deleted 'no_student_token' policy."