#!/bin/bash
# Define the MySQL credentials and database

DB_USER="{{ mariadb_user }}"
DB_NAME="{{ privacyidea_mariadb_name }}"
DB_HOST="{{ privacyidea_mariadb_host }}"
DB_PASSWORD="{{ privacyidea_db_user_password }}"
DUMP_FILE="{{ dump_file }}"
DESIRED_TOKEN_COUNT={{ desired_token_count | int }} 

# Verify the token count before importing the SQL dump
# It is checked before starting the import if reimport is needed by checking the desired token count. 
echo "Checking current token count"
TOKEN_COUNT=$(mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME -sse "SELECT COUNT(*) FROM token;")
if [ "$TOKEN_COUNT" -eq $DESIRED_TOKEN_COUNT ]; then
  echo "Token count is already correct: $TOKEN_COUNT. No need to import the dump file."
  exit 0
elif [ "$TOKEN_COUNT" -eq 0 ] || [ "$TOKEN_COUNT" -lt $DESIRED_TOKEN_COUNT ]; then
  echo "Token count is $TOKEN_COUNT, which is less than $DESIRED_TOKEN_COUNT. Proceeding with SQL dump import..."
  
  # Import the SQL dump
  if [ -f  /var/backups/$DUMP_FILE ]; then
    mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME < /var/backups/$DUMP_FILE
    echo "SQL dump imported."
  else
    echo No Backupfile found
    exit 1
  fi
  
  # Verify the token count again after import
  TOKEN_COUNT_AFTER_IMPORT=$(mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME -sse "SELECT COUNT(*) FROM token;")
  if [ "$TOKEN_COUNT_AFTER_IMPORT" -ne $DESIRED_TOKEN_COUNT ]; then
    echo "Error: Token count is $TOKEN_COUNT_AFTER_IMPORT after import, but it should be $DESIRED_TOKEN_COUNT."
  else
    echo "Token count is correct after import: $TOKEN_COUNT_AFTER_IMPORT"
  fi
else
  echo "Error: Unexpected token count: $TOKEN_COUNT"
  exit 1
fi

# Remove existing admin users
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "DELETE FROM admin;"
echo "Existing admin users deleted."

# Create new admin users
sudo -u www-data /opt/privacyidea/virtualenv/bin/pi-manage admin add admin --password "{{ privacyidea_admin_password }}"
sudo -u www-data /opt/privacyidea/virtualenv/bin/pi-manage admin add token-admin --password "{{ privacyidea_token_admin_password }}"
sudo -u www-data /opt/privacyidea/virtualenv/bin/pi-manage admin add seed-import --password "{{ privacyidea_seed_import_password }}"
echo "New admin users created."

# Drop & Recreate users_service table
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "
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
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "
  SET FOREIGN_KEY_CHECKS = 0;
  DELETE FROM resolverconfig;
"
echo "Deleted ldap resolverconfig."

# Update existing service sqlresolver
sudo -u www-data /opt/privacyidea/virtualenv/bin/pi-manage resolver create service sqlresolver /etc/privacyidea/user_sql_resolver_config.ini

# Create two new sqlresolvers
sudo -u www-data /opt/privacyidea/virtualenv/bin/pi-manage resolver create domain_admins sqlresolver /etc/privacyidea/admin_sql_resolver_config.ini
sudo -u www-data /opt/privacyidea/virtualenv/bin/pi-manage resolver create domain_users sqlresolver /etc/privacyidea/user_sql_resolver_config.ini
echo "Created domain_admins and domain_users sqlresolvers."

# Determine the resolver_id of the domain_admins and domain_users resolvers and store them in a variable
RESOLVER_ID_DOMAIN_USERS=$(mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD -N -s -e "SELECT id FROM resolver WHERE name = 'domain_users';" $DB_NAME)
RESOLVER_ID_DOMAIN_ADMIN=$(mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD -N -s -e "SELECT id FROM resolver WHERE name = 'domain_admins';" $DB_NAME)

# Return the new resolver_id
echo "The resolver ID for 'domain_users' is: $RESOLVER_ID_DOMAIN_USERS"
echo "The resolver ID for 'domain_admin' is: $RESOLVER_ID_DOMAIN_ADMIN"

# Remove ldap resolvers
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "
  SET FOREIGN_KEY_CHECKS = 0;
  DELETE FROM resolver WHERE id IN (6);
  DELETE FROM resolver WHERE id IN (9);
"
echo "Deleted ldap resolvers."

# Update resolver IDs and names
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "
     SET FOREIGN_KEY_CHECKS = 0;
     UPDATE resolver SET id = 6, name = 'ucs_users' WHERE name = 'domain_users';
     UPDATE resolver SET id = 9, name = 'ucs_domain_admins' WHERE name = 'domain_admins';
     UPDATE resolverconfig SET resolver_id = 6 WHERE resolver_id = $RESOLVER_ID_DOMAIN_USERS;
     UPDATE resolverconfig SET resolver_id = 9 WHERE resolver_id = $RESOLVER_ID_DOMAIN_ADMIN;
     SET FOREIGN_KEY_CHECKS = 1;
"
echo "Updated resolver IDs and names."

# Separate step to delete specific policy conditions
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "
  SET FOREIGN_KEY_CHECKS = 0;
  DELETE FROM policycondition WHERE policy_id IN (SELECT id FROM policy WHERE name = 'no_student_token');
  DELETE FROM policy WHERE name = 'no_student_token';
  SET FOREIGN_KEY_CHECKS = 1;
"
echo "Deleted 'no_student_token' policy."

# Insert the new 'self-service' policy
echo "Inserting new 'self-service' policy..."
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "
INSERT INTO policy (active, check_all_resolvers, name, scope, action, realm, adminrealm, adminuser, resolver, pinode, user, client, time, priority)
VALUES (1, 0, 'self-service', 'enrollment', 'verify_enrollment=totp', '', '', '', '', '', '', '', '', 5);
"
echo "New 'self-service' policy added."

# Retrieve the new policy ID
POLICY_ID=$(mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD -N -s -e "SELECT id FROM policy WHERE name = 'self-service';" $DB_NAME)
echo "The new policy ID for 'self-service' is: $POLICY_ID"

# Insert the new condition for the policy in the 'policycondition' table
echo "Inserting policy condition for the new policy..."
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "
INSERT INTO policycondition (policy_id, section, \`Key\`, comparator, Value, active)
VALUES ($POLICY_ID, 'HTTP Request header', 'SelfService', 'equals', 'true', 1);
"
echo "Policy condition added."

# Create periodic tasks for various counting operations
# Create event handlers for various events
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "
INSERT INTO periodictask (name, active,\`interval\`, nodes, taskmodule, ordering, last_update, retry_if_failed) VALUES
    ('Count Successful Authentications', 1, '*/5 * * * *', 'localnode', 'EventCounter', 1, NOW(), 1),
    ('Count Failed Authentications', 1, '*/5 * * * *', 'localnode', 'EventCounter', 2, NOW(), 1),
    ('Count Token Initializations', 1, '*/5 * * * *', 'localnode', 'EventCounter', 3, NOW(), 1),
    ('Count Token Assignments', 1, '*/5 * * * *', 'localnode', 'EventCounter', 4, NOW(), 1),
    ('Count Token Unassignments', 1, '*/5 * * * *', 'localnode', 'EventCounter', 5, NOW(), 1),
    ('Count New Users', 1, '*/5 * * * *', 'localnode', 'EventCounter', 6, NOW(), 1),
    ('Update Token Statistics', 1, '*/5 * * * *', 'localnode', 'SimpleStats', 7, NOW(), 1);

INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'event_counter', 'successful_auth_counter' FROM periodictask WHERE name = 'Count Successful Authentications';
INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'stats_key', 'successful_auth_counter' FROM periodictask WHERE name = 'Count Successful Authentications';
INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'reset_event_counter', 'True' FROM periodictask WHERE name = 'Count Successful Authentications';

INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'event_counter', 'failed_auth_counter' FROM periodictask WHERE name = 'Count Failed Authentications';
INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'stats_key', 'failed_auth_counter' FROM periodictask WHERE name = 'Count Failed Authentications';
INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'reset_event_counter', 'True' FROM periodictask WHERE name = 'Count Failed Authentications';

INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'event_counter', 'token_init_counter' FROM periodictask WHERE name = 'Count Token Initializations';
INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'stats_key', 'token_init_counter' FROM periodictask WHERE name = 'Count Token Initializations';
INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'reset_event_counter', 'True' FROM periodictask WHERE name = 'Count Token Initializations';

INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'event_counter', 'token_assign_counter' FROM periodictask WHERE name = 'Count Token Assignments';
INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'stats_key', 'token_assign_counter' FROM periodictask WHERE name = 'Count Token Assignments';
INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'reset_event_counter', 'True' FROM periodictask WHERE name = 'Count Token Assignments';

INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'event_counter', 'token_unassign_counter' FROM periodictask WHERE name = 'Count Token Unassignments';
INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'stats_key', 'token_unassign_counter' FROM periodictask WHERE name = 'Count Token Unassignments';
INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'reset_event_counter', 'True' FROM periodictask WHERE name = 'Count Token Unassignments';

INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'event_counter', 'new_users_counter' FROM periodictask WHERE name = 'Count New Users';
INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'stats_key', 'new_users_counter' FROM periodictask WHERE name = 'Count New Users';
INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'reset_event_counter', 'True' FROM periodictask WHERE name = 'Count New Users';

INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'total_tokens', 'True' FROM periodictask WHERE name = 'Update Token Statistics';
INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'hardware_tokens', 'True' FROM periodictask WHERE name = 'Update Token Statistics';
INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'software_tokens', 'True' FROM periodictask WHERE name = 'Update Token Statistics';
INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'assigned_tokens', 'True' FROM periodictask WHERE name = 'Update Token Statistics';
INSERT INTO periodictaskoption (periodictask_id, \`Key\`, value)
    SELECT id, 'unassigned_hardware_tokens', 'True' FROM periodictask WHERE name = 'Update Token Statistics';

INSERT INTO eventhandler (name, active, ordering, position, event, handlermodule, action) VALUES
    ('Successful Authentication', 1, 1, 'post', 'validate_check', 'Counter', 'increase_counter'),
    ('Failed Authentication', 1, 2, 'post', 'validate_check', 'Counter', 'increase_counter'),
    ('Token Initialization', 1, 3, 'post', 'token_init', 'Counter', 'increase_counter'),
    ('Token Assignment', 1, 4, 'post', 'token_assign', 'Counter', 'increase_counter'),
    ('New User Created', 1, 5, 'post', 'user_add', 'Counter', 'increase_counter'),
    ('Token Unassignment', 1, 6, 'post', 'token_unassign', 'Counter', 'increase_counter'),
    ('Update Token Statistics', 1, 7, 'post', 'update_statistics', 'SimpleStats', 'update_statistics');

INSERT INTO eventhandleroption (eventhandler_id, \`Key\`, Value, Type, Description)
    SELECT id, 'counter_name', 'successful_auth_counter', 'string', 'Counter name for successful authentications' FROM eventhandler WHERE name = 'Successful Authentication';
INSERT INTO eventhandleroption (eventhandler_id, \`Key\`, Value, Type, Description)
    SELECT id, 'counter_name', 'failed_auth_counter', 'string', 'Counter name for failed authentications' FROM eventhandler WHERE name = 'Failed Authentication';
INSERT INTO eventhandleroption (eventhandler_id, \`Key\`, Value, Type, Description)
    SELECT id, 'counter_name', 'token_init_counter', 'string', 'Counter name for token initializations' FROM eventhandler WHERE name = 'Token Initialization';
INSERT INTO eventhandleroption (eventhandler_id, \`Key\`, Value, Type, Description)
    SELECT id, 'counter_name', 'token_assign_counter', 'string', 'Counter name for Token Assignment' FROM eventhandler WHERE name = 'Token Assignment';
INSERT INTO eventhandleroption (eventhandler_id, \`Key\`, Value, Type, Description)
    SELECT id, 'counter_name', 'new_users_counter', 'string', 'Counter name for New User Created' FROM eventhandler WHERE name = 'New User Created';
INSERT INTO eventhandleroption (eventhandler_id,\`Key\`, Value, Type, Description)
    SELECT id, 'counter_name', 'token_unassign_counter', 'string', 'Counter name for token unassignments' FROM eventhandler WHERE name = 'Token Unassignment';

INSERT INTO eventhandlercondition (eventhandler_id, \`Key\`, Value, comparator)
    SELECT eventhandler_id, 'result_value', 'True', '=' FROM eventhandleroption WHERE Value = 'successful_auth_counter';
INSERT INTO eventhandlercondition (eventhandler_id, \`Key\`, Value, comparator)
    SELECT eventhandler_id, 'result_value', 'False', '=' FROM eventhandleroption WHERE Value = 'failed_auth_counter';
INSERT INTO eventhandlercondition (eventhandler_id, \`Key\`, Value, comparator)
    SELECT eventhandler_id, 'tokentype', 'hotp', '=' FROM eventhandleroption WHERE Value = 'token_init_counter';
INSERT INTO eventhandlercondition (eventhandler_id, \`Key\`, Value, comparator)
    SELECT eventhandler_id, 'token_has_owner', 'True', '=' FROM eventhandleroption WHERE Value = 'token_assign_counter';
INSERT INTO eventhandlercondition (eventhandler_id, \`Key\`, Value, comparator)
    SELECT eventhandler_id, 'token_has_owner', 'False', '=' FROM eventhandleroption WHERE Value = 'token_unassign_counter';

INSERT INTO eventhandleroption (eventhandler_id, \`Key\`, Value, Type, Description)
    SELECT id, 'total_tokens', 'True', 'boolean', 'Include total number of tokens' FROM eventhandler WHERE name = 'Update Token Statistics';
INSERT INTO eventhandleroption (eventhandler_id, \`Key\`, Value, Type, Description)
    SELECT id, 'hardware_tokens', 'True', 'boolean', 'Include number of hardware tokens' FROM eventhandler WHERE name = 'Update Token Statistics';
INSERT INTO eventhandleroption (eventhandler_id, \`Key\`, Value, Type, Description)
    SELECT id, 'software_tokens', 'True', 'boolean', 'Include number of software tokens' FROM eventhandler WHERE name = 'Update Token Statistics';
INSERT INTO eventhandleroption (eventhandler_id, \`Key\`, Value, Type, Description)
    SELECT id, 'assigned_tokens', 'True', 'boolean', 'Include number of assigned tokens' FROM eventhandler WHERE name = 'Update Token Statistics';
INSERT INTO eventhandleroption (eventhandler_id, \`Key\`, Value, Type, Description)
    SELECT id, 'unassigned_hardware_tokens', 'True', 'boolean', 'Include number of unassigned hardware tokens' FROM eventhandler WHERE name = 'Update Token Statistics';

ALTER TABLE pidea_audit MODIFY COLUMN info VARCHAR(1000);
ALTER TABLE pidea_audit MODIFY COLUMN action VARCHAR(100);
ALTER TABLE pidea_audit MODIFY COLUMN action_detail VARCHAR(100);
ALTER TABLE pidea_audit MODIFY COLUMN policies VARCHAR(1000);

"