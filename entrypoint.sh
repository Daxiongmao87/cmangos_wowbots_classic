#!/bin/bash
MYSQL_PATH=$(whereis mysql | cut -d ' ' -f2)
CORE_PATH=$HOME/server/mangos

# Set ADMIN_USERNAME and ADMIN_PASSWORD default values if not provided
ADMIN_USER=${ADMIN_USER:-admin}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
# Create /run/mysqld directory with correct permissions
sudo mkdir -p /run/mysqld
sudo chown mysql:mysql /run/mysqld
sudo chmod 777 /run/mysqld
sudo chown -R mangos:mangos $HOME/server
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "Initializing MariaDB Data Directory"
    sudo mysql_install_db --user=mysql --ldata=/var/lib/mysql

fi

# Start MariaDB service
sudo touch /var/log/mysqld.log
sudo chown mysql:mysql /var/log/mysqld.log

echo "Starting MariaDB service..."
sudo su -s /bin/bash -c "mysqld_safe --log-error=/var/log/mysqld.log &" mysql
echo "MariaDB service started..."
sleep 1
# Wait for MariaDB to fully initialize
while ! mysqladmin ping --silent; do
    echo "Waiting (10s) for MariaDB to start..."
    sleep 10
done
echo "MariaDB started successfully."
# Setup MariaDB databases and user
# Check if the mangos user exists and create if it does not
sudo mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$MYSQL_ROOT_PASSWORD');"
sudo mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"
echo "Checking if user mangos exists..."
USER_EXISTS=$(mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -se "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = 'mangos' AND host = 'localhost');")
if [ "$USER_EXISTS" = 1 ]; then
    echo "User mangos already exists."
else
    echo "User mangos does not exist. Creating user mangos..."
    mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER 'mangos'@'localhost' IDENTIFIED BY 'mangos';"
    mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON *.* TO 'mangos'@'localhost';"
    mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"
fi

# Set names for databases
MANGOS_DBNAME="${WOW_EXPANSION}mangos"
CHARACTERS_DBNAME="${WOW_EXPANSION}characters"
REALMD_DBNAME="${WOW_EXPANSION}realmd"

# Check if the databases already exist and create them if they do not
echo "Checking if databases exist..."
for DB in $MANGOS_DBNAME $CHARACTERS_DBNAME $REALMD_DBNAME; do
    DB_EXISTS=$(mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -se "SHOW DATABASES LIKE '$DB';")
    if [ "$DB_EXISTS" = "$DB" ]; then
        echo "Database $DB already exists."
    else
        echo "Database $DB does not exist. Creating..."
        mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE $DB;"
        mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON $DB.* TO 'mangos'@'localhost';"
    fi
done
mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

# Check if the mangos database exists and has the necessary tables
DB_EXISTS=$(mysql -umangos -pmangos -se "SHOW DATABASES LIKE '$MANGOS_DBNAME';")
TABLE_EXISTS=$(mysql -umangos -pmangos -se "SHOW TABLES IN $MANGOS_DBNAME LIKE 'ai_playerbot_enchants';")

if [ "$DB_EXISTS" = "$MANGOS_DBNAME" ] && [ "$TABLE_EXISTS" = "ai_playerbot_enchants" ]; then
    echo "${WOW_EXPANSION}-DB with playerbots already set up. Skipping..."
else
    echo "Setting up ${WOW_EXPANSION}-DB with playerbots enabled..."
    echo "Removing creation of default accounts..."
    sed -i '/-- Dumping data for table `account`/,/UNLOCK TABLES;/d' $CORE_PATH/sql/base/realmd.sql
    echo "Removed default account creation sql statements."
    cd $HOME/server/database
    chmod +x InstallFullDB.sh
    # Initialize InstallFullDB.config by running InstallFullDB.sh silently
    echo "Generating InstallFullDB.config..."
    sed -i 's/clear/:/g' InstallFullDB.sh
    ./InstallFullDB.sh &> /dev/null
    # Update InstallFullDB.config to enable playerbotis
    echo "Updating InstallFullDB.config..."
    sed -i 's|PLAYERBOTS_DB="NO"|PLAYERBOTS_DB="YES"|g' InstallFullDB.config
    sed -i 's|AHBOT="NO"|AHBOT="YES"|g' InstallFullDB.config
    echo "Running InstallFullDB.sh to setup ${WOW_EXPANSION}-DB with playerbots..."
    sed -i "s|MYSQL_PATH=\"\"|MYSQL_PATH=\"$MYSQL_PATH\"|g" InstallFullDB.config
    sed -i "s|CORE_PATH=\"\"|CORE_PATH=\"$CORE_PATH\"|g" InstallFullDB.config
    export TERM=xterm
    ./InstallFullDB.sh -InstallAll root $MYSQL_ROOT_PASSWORD DeleteAll
    echo "Success? $?"
    echo "${WOW_EXPANSION}-DB setup with playerbots enabled successfully."
    init_accounts="true"
fi

# Update reamlist table in the realmd database to match SERVER_ADDRESS
echo "Updating realmlist entry's address in the '${WOW_EXPANSION}realmd' database..."
mysql -umangos -pmangos -e "UPDATE ${WOW_EXPANSION}realmd.realmlist SET address = '$SERVER_ADDRESS';"
updated_realm=$(mysql -umangos -pmangos -se "SELECT address FROM ${WOW_EXPANSION}realmd.realmlist;")
echo "Realmlist table updated to $updated_realm."

# Update realmlist table in the realmd database to match SERVER_NAME
echo "Updating realmlist entry's name in the '${WOW_EXPANSION}realmd' database..."
mysql -umangos -pmangos -e "UPDATE ${WOW_EXPANSION}realmd.realmlist SET name = '$SERVER_NAME';"
updated_realm=$(mysql -umangos -pmangos -se "SELECT name FROM ${WOW_EXPANSION}realmd.realmlist;")
echo "Realmlist table updated to $updated_realm."


# Apply SQL updates to the 'characters' database
BOTS_SQL_DIR="$CORE_PATH/src/modules/PlayerBots/sql"
echo "Applying playerbots SQL updates to the 'characters' database..."
for sql_file in $BOTS_SQL_DIR/characters/*.sql; do
    # Extract table name from SQL file
    TABLE_NAME=$(grep -oP 'CREATE TABLE `\K\w+' "$sql_file")
    # Check if table exists
    TABLE_EXISTS=$(mysql -umangos -pmangos -se "SHOW TABLES LIKE '$TABLE_NAME';" "$CHARACTERS_DBNAME")
    if [ "$TABLE_EXISTS" = "$TABLE_NAME" ]; then
        echo "Table $TABLE_NAME already exists. Skipping $sql_file..."
    else
        echo "Applying $sql_file..."
        mysql -umangos -pmangos "$CHARACTERS_DBNAME" < "$sql_file"
    fi
done
echo "Character database updated successfully."

# Apply SQL updates to the 'world' database
echo "Applying playerbots SQL updates to the 'world' database..."
for sql_file in $BOTS_SQL_DIR/world/*.sql; do
    # Extract table name from SQL file
    TABLE_NAME=$(grep -oP 'CREATE TABLE `\K\w+' "$sql_file")
    # Check if table exists
    TABLE_EXISTS=$(mysql -umangos -pmangos -se "SHOW TABLES LIKE '$TABLE_NAME';" $MANGOS_DBNAME)
    if [ "$TABLE_EXISTS" = "$TABLE_NAME" ]; then
        echo "Table $TABLE_NAME already exists. Skipping $sql_file..."
    else
        echo "Applying $sql_file..."
        mysql -umangos -pmangos $MANGOS_DBNAME < "$sql_file"
    fi
done
echo "World database updated successfully."

# Apply expansion-specific SQL updates to the 'world' database
echo "Applying playerbots SQL updates to the 'world' database for the ${WOW_EXPANSION} expansion..."
for sql_file in $BOTS_SQL_DIR/world/${WOW_EXPANSION}/*.sql; do
    # Extract table name from SQL file
    TABLE_NAME=$(grep -oP 'CREATE TABLE `\K\w+' "$sql_file")
    # Check if table exists
    TABLE_EXISTS=$(mysql -umangos -pmangos -se "SHOW TABLES LIKE '$TABLE_NAME';" $MANGOS_DBNAME)
    if [ "$TABLE_EXISTS" = "$TABLE_NAME" ]; then
        echo "Table $TABLE_NAME already exists. Skipping $sql_file..."
    else
        echo "Applying $sql_file..."
        mysql -umangos -pmangos $MANGOS_DBNAME < "$sql_file"
    fi
done
echo "World database for the ${WOW_EXPANSION} expansion updated successfully."

# Copy aiplayerbot.conf
mkdir -p $HOME/server/run/etc
if [ -f $HOME/server/run/etc/aiplayerbot.conf ]; then
    echo "aiplayerbot.conf already exists. Skipping..."
else
    echo "Copying aiplayerbot.conf..."
    cp $HOME/server/mangos/build/src/modules/PlayerBots/aiplayerbot.conf.dist $HOME/server/run/etc/aiplayerbot.conf
fi
if [ -f $HOME/server/run/etc/ahbot.conf ]; then
    echo "ahbot.conf already exists. Skipping..."
else
    echo "Copying ahbot.conf..."
    cp $HOME/server/mangos/build/src/modules/PlayerBots/ahbot.conf.dist $HOME/server/run/etc/ahbot.conf
fi

# Assuming client files are mounted at $HOME/client
echo "Extracting client data..."
CLIENT_PATH="$HOME/client"
EXTRACTION_OUTPUT="$HOME/server/client-data"
mkdir -p $EXTRACTION_OUTPUT

# Check if client data exists
echo "Checking for WoW client data..."
if [ ! -d "$CLIENT_PATH/Data" ]; then
    echo "WoW client files not found in $CLIENT_PATH."
    exit 1
fi
echo "WoW client files found in $CLIENT_PATH."

# Run the extraction scripts (Assuming they're compiled and available in the run/bin/tools directory)
# Check if data is already extracted
if [ "$(ls -A $EXTRACTION_OUTPUT/vmaps)" ]; then
    echo "Client data already extracted. Skipping..."
else
    echo "Client data not extracted. Extracting..."
    cd $HOME/server/run/bin/tools
    ./ExtractResources.sh a $CLIENT_PATH $EXTRACTION_OUTPUT
    echo "Client data extracted successfully."
fi

# Define the directories to check and move
#DIRS=("maps" "dbc" "vmaps" "mmaps" "CreatureModels" "Cameras")
DIRS=("maps" "dbc" "vmaps" "mmaps" "Buildings" "Cameras")

# Ensure the extracted data is moved to the correct directories
for DIR in "${DIRS[@]}"; do
        if [ "$(ls -A $HOME/server/run/bin/$DIR)" ]; then
        echo "$DIR already copied to the correct directory. Skipping..."
    else
        if [ -d "$EXTRACTION_OUTPUT/$DIR" ]; then
            echo "Copying $DIR to the correct directory..."
            cp -r "$EXTRACTION_OUTPUT/$DIR/" "$HOME/server/run/bin/"
            echo "$DIR moved successfully."
        else
            echo "$DIR does not exist in the extraction output. Skipping..."
        fi
    fi
done

# Copy mangosd.conf.dist and realmd.conf.dist to the etc directory
if [ -f $HOME/server/run/etc/mangosd.conf ]; then
    echo "mangosd.conf already exists. Skipping..."
else
    echo "Copying mangosd.conf..."
    cp $CORE_PATH/src/mangosd/mangosd.conf.dist.in $HOME/server/run/etc/mangosd.conf
    echo "mangosd.conf copied successfully."
fi

if [ -f $HOME/server/run/etc/realmd.conf ]; then
    echo "realmd.conf already exists. Skipping..."
else
    echo "Copying realmd.conf..."
    cp $CORE_PATH/src/realmd/realmd.conf.dist.in $HOME/server/run/etc/realmd.conf
    echo "realmd.conf copied successfully."
fi

# Start the CMaNGOS server
cd $HOME/server/run/bin

echo "Starting CMaNGOS server..."
screen -dmS mangosd ./mangosd -c $HOME/server/run/etc/mangosd.conf
echo "CMaNGOS server started in detached screen."

# Start the realmd service
echo "Starting realmd..."
screen -dmS realmd ./realmd -c $HOME/server/run/etc/realmd.conf
echo "Realmd started successfully."

#Update website's config.php with the mysql information
CONFIG_PHP="$HOME/server/website/application/config.php"
sed -i "s/define('DB_HOST', '.*');/define('DB_HOST', '127.0.0.1');/" $CONFIG_PHP
sed -i "s/define('DB_USERNAME', '.*');/define('DB_USERNAME', 'root');/" $CONFIG_PHP
sed -i "s/define('DB_PASSWORD', '.*');/define('DB_PASSWORD', 'root');/" $CONFIG_PHP
sed -i "s/define('DB_REALMD', '.*');/define('DB_REALMD', '${WOW_EXPANSION}realmd');/" $CONFIG_PHP
sed -i "s/'mangosd_${WOW_EXPANSION}'/'$MANGOS_DBNAME'/" $CONFIG_PHP
sed -i "s/'characters_${WOW_EXPANSION}'/'"$CHARACTERS_DBNAME"'/" $CONFIG_PHP
sed -i "s/define('WEBSITE_NAME', '.*');/define('WEBSITE_NAME', '$SERVER_NAME');/" $CONFIG_PHP
sed -i "s/define('WEBSITE_TIMEZONE', '.*');/define('WEBSITE_TIMEZONE', '${TIMEZONE//\//\\/}');/" $CONFIG_PHP


# Configure Nginx and PHP
sudo bash -c 'cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 8080;
    server_name localhost;

    root /var/www/html;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    location ~ /\.ht {
        deny all;
    }
}
EOF'
# Update PHP configuration
echo "Enabling short_open_tag in php.ini..."
sudo sed -i 's/^short_open_tag = Off/short_open_tag = On/' /etc/php/8.1/fpm/php.ini

sudo rm -rf /var/www/html/*
sudo cp -r $HOME/server/website/* /var/www/html
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html

# Configure php-fpm to log to console
sudo mkdir -p /usr/local/etc/php-fpm.d
sudo bash -c 'cat <<EOF > /usr/local/etc/php-fpm.d/logging.conf
[global]
error_log = /proc/self/fd/2

[www]
access.log = /proc/self/fd/2

catch_workers_output = yes
decorate_workers_output = no
EOF'

# Start the Nginx service
echo "Starting Nginx and php-fpm services..."
sudo nginx -g 'daemon off;' &
sudo php-fpm8.1 -F &
echo "Nginx started."
while ! curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "^2"; do
    sleep 5
done

case "${WOW_EXPANSION}" in
    "classic")
        WOW_VERSION="1.21.1"
        ;;
    "tbc")
        WOW_VERSION="2.4.3"
        ;;
    "wotlk")
        WOW_VERSION="3.3.5a"
        ;;
    *)
        WOW_VERSION="i dunno"
        ;;
esac

website_db_exists=$(mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -se "SHOW DATABASES LIKE 'website';")
if [ "$website_db_exists" != "website" ]; then
    echo "website database does not exist. Creating website database..."
    echo "Importing website.sql..."
    mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE website;"
    mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON website.* TO 'mangos'@'localhost';"
    mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"
    mysql -umangos -pmangos website < $HOME/server/website/website.sql
    echo "website.sql imported successfully."
    echo "Checking if admin account exists..."
    ADMIN_EXISTS=$(mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -se "SELECT EXISTS(SELECT 1 FROM ${WOW_EXPANSION}realmd.account WHERE username = '$ADMIN_USER');")
    if [ "$ADMIN_EXISTS" != 1 ]; then
        curl localhost:8080/account/create -s -o /dev/null -X POST --data-raw "username=$(urlencode "$ADMIN_USER")&email=noreply%40noreply.com&password=$(urlencode "$ADMIN_PASSWORD")&password_confirm=$(urlencode "$ADMIN_PASSWORD")"
        echo "Admin account created successfully."
    fi
    admin_id=$(mysql -umangos -pmangos -se "SELECT id FROM website.account WHERE nickname = '$ADMIN_USER';")
    echo "Inserting news entry..."
    mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "\
        INSERT INTO website.news VALUES ('1', '$(date +%s)', '$admin_id', '${SERVER_NAME} is Now Live! Rediscover ${WOW_EXPANSION} Azeroth', 'Welcome back to the ${WOW_EXPANSION} era of World of Warcraft with [b]${SERVER_NAME}[/b]! Immerse yourself in the original, unaltered Azeroth as it was meant to be experienced.\n\
        \n\
        [b]Key Features:[/b]\n\
        - [b]Authentic Blizzlike Gameplay:[/b] Every aspect of the server replicates the ${WOW_EXPANSION} ${WOW_VERSION} experience.\n\
        - [b]Enhanced by Bots:[/b] To ensure a thriving environment, our server includes bots that simulate a populated world, making it easy to find allies for your adventures.\n\
        \n\
        [b]Get Started:[/b]\n\
        1. [b]Download the ${WOW_VERSION} Client:[/b] If you don\'t already have it, download the ${WOW_EXPANSION} version ${WOW_VERSION} client.\n\
        2. [b]Edit Your Realmlist.wtf File:[/b] Navigate to your WoW directory, open the \'realmlist.wtf\' file with a text editor, and replace its contents with: `set realmlist ${SERVER_ADDRESS}`.\n\
        3. [b]Create an Account:[/b] Visit ${WEBSITE_PUBLIC_URL} to register.\n\
        4. [b]Log In and Play:[/b] Enter the world and start your ${WOW_EXPANSION} adventure!\n\
        \n\
        Sign up at [b]${SERVER_NAME}/account/create[/b] and relive the legendary tales of Azeroth as they were originally told!', '1');"
    echo "News entry inserted successfully."
    echo "Website setup complete."
fi

echo "-------------------------------_"
echo "[MariaDB] is now running. To monitor logs, use: docker exec -t $HOSTNAME monitor mariadb"
echo "[Mangosd] is now running. To monitor logs, use: docker exec -t $HOSTNAME monitor mangosd"
echo "[Realmd]  is now running. To monitor logs, use: docker exec -t $HOSTNAME monitor realmd"
echo "[Website] is now running. To monitor logs, use: docker exec -t $HOSTNAME monitor website"
while true; do
    if ! pgrep -x "mysqld_safe" > /dev/null; then
        echo "MariaDB service has stopped. Exiting..."
        exit 1
    fi
    if ! pgrep -x "mangosd" > /dev/null; then
        echo "Mangosd service has stopped. Exiting..."
        exit 1
    fi
    if ! pgrep -x "realmd" > /dev/null; then
        echo "Realmd service has stopped. Exiting..."
        exit 1
    fi
    if ! curl -s "http://localhost:8080" > /dev/null; then
        echo "Website service has stopped. Exiting..."
        exit 1
    fi
    sleep 5
done
