#!/bin/bash
MYSQL_PATH=$(whereis mysql | cut -d ' ' -f2)
HOME_PATH=/home/mangos
CORE_PATH=$HOME_PATH/server/mangos

# Set ADMIN_USERNAME and ADMIN_PASSWORD default values if not provided
ADMIN_USERNAME=${ADMIN_USERNAME:-ADMINISTRATOR}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-ADMINISTRATOR}
# Create /run/mysqld directory with correct permissions
sudo mkdir -p /run/mysqld
sudo chown mysql:mysql /run/mysqld
sudo chmod 777 /run/mysqld
sudo chown -R mangos:mangos $HOME_PATH/server
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

# Check if the databases already exist and create them if they do not
echo "Checking if databases exist..."
for DB in classicmangos classiccharacters classicrealmd; do
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

# Check if the 'classicmangos' database exists and has the necessary tables
DB_EXISTS=$(mysql -umangos -pmangos -se "SHOW DATABASES LIKE 'classicmangos';")
TABLE_EXISTS=$(mysql -umangos -pmangos -se "SHOW TABLES IN classicmangos LIKE 'ai_playerbot_enchants';")

if [ "$DB_EXISTS" = "classicmangos" ] && [ "$TABLE_EXISTS" = "ai_playerbot_enchants" ]; then
    echo "Classic-DB with playerbots already set up. Skipping..."
else
    echo "Setting up Classic-DB with playerbots enabled..."
    cd $HOME_PATH/server/database
    chmod +x InstallFullDB.sh
    # Initialize InstallFullDB.config by running InstallFullDB.sh silently
    echo "Generating InstallFullDB.config..."
    sed -i 's/clear/:/g' InstallFullDB.sh
    ./InstallFullDB.sh &> /dev/null
    # Update InstallFullDB.config to enable playerbotis
    echo "Updating InstallFullDB.config..."
    sed -i 's|PLAYERBOTS_DB="NO"|PLAYERBOTS_DB="YES"|g' InstallFullDB.config
    sed -i 's|AHBOT="NO"|AHBOT="YES"|g' InstallFullDB.config
    echo "Running InstallFullDB.sh to setup Classic-DB with playerbots..."
    sed -i "s|MYSQL_PATH=\"\"|MYSQL_PATH=\"$MYSQL_PATH\"|g" InstallFullDB.config
    sed -i "s|CORE_PATH=\"\"|CORE_PATH=\"$CORE_PATH\"|g" InstallFullDB.config
    export TERM=xterm
    ./InstallFullDB.sh -InstallAll root $MYSQL_ROOT_PASSWORD DeleteAll
    echo "Success? $?"
    echo "Classic-DB setup with playerbots enabled successfully."
    init_accounts="true"
fi

# Update reamlist table in the 'classicrealmd' database to match SERVER_ADDRESS
echo "Updating realmlist entry's address in the 'classicrealmd' database..."
mysql -umangos -pmangos -e "UPDATE classicrealmd.realmlist SET address = '$SERVER_ADDRESS';"
updated_realm=$(mysql -umangos -pmangos -se "SELECT address FROM classicrealmd.realmlist;")
echo "Realmlist table updated to $updated_realm."

# Update realmlist table in the 'classicrealmd' database to match SERVER_NAME
echo "Updating realmlist entry's name in the 'classicrealmd' database..."
mysql -umangos -pmangos -e "UPDATE classicrealmd.realmlist SET name = '$SERVER_NAME';"
updated_realm=$(mysql -umangos -pmangos -se "SELECT name FROM classicrealmd.realmlist;")
echo "Realmlist table updated to $updated_realm."


# Apply SQL updates to the 'characters' database
BOTS_SQL_DIR="$CORE_PATH/src/modules/Bots/sql"
echo "Applying playerbots SQL updates to the 'characters' database..."
for sql_file in $BOTS_SQL_DIR/characters/*.sql; do
    # Extract table name from SQL file
    TABLE_NAME=$(grep -oP 'CREATE TABLE `\K\w+' "$sql_file")
    # Check if table exists
    TABLE_EXISTS=$(mysql -umangos -pmangos -se "SHOW TABLES LIKE '$TABLE_NAME';" classiccharacters)
    if [ "$TABLE_EXISTS" = "$TABLE_NAME" ]; then
        echo "Table $TABLE_NAME already exists. Skipping $sql_file..."
    else
        echo "Applying $sql_file..."
        mysql -umangos -pmangos classiccharacters < "$sql_file"
    fi
done
echo "Character database updated successfully."

# Apply SQL updates to the 'world' database
echo "Applying playerbots SQL updates to the 'world' database..."
for sql_file in $BOTS_SQL_DIR/world/*.sql; do
    # Extract table name from SQL file
    TABLE_NAME=$(grep -oP 'CREATE TABLE `\K\w+' "$sql_file")
    # Check if table exists
    TABLE_EXISTS=$(mysql -umangos -pmangos -se "SHOW TABLES LIKE '$TABLE_NAME';" classicmangos)
    if [ "$TABLE_EXISTS" = "$TABLE_NAME" ]; then
        echo "Table $TABLE_NAME already exists. Skipping $sql_file..."
    else
        echo "Applying $sql_file..."
        mysql -umangos -pmangos classicmangos < "$sql_file"
    fi
done
echo "World database updated successfully."

# Apply expansion-specific SQL updates to the 'world' database
echo "Applying playerbots SQL updates to the 'world' database for the Classic expansion..."
for sql_file in $BOTS_SQL_DIR/world/classic/*.sql; do
    # Extract table name from SQL file
    TABLE_NAME=$(grep -oP 'CREATE TABLE `\K\w+' "$sql_file")
    # Check if table exists
    TABLE_EXISTS=$(mysql -umangos -pmangos -se "SHOW TABLES LIKE '$TABLE_NAME';" classicmangos)
    if [ "$TABLE_EXISTS" = "$TABLE_NAME" ]; then
        echo "Table $TABLE_NAME already exists. Skipping $sql_file..."
    else
        echo "Applying $sql_file..."
        mysql -umangos -pmangos classicmangos < "$sql_file"
    fi
done
echo "World database for the Classic expansion updated successfully."

# Copy aiplayerbot.conf
mkdir -p $HOME_PATH/server/run/etc
if [ -f $HOME_PATH/server/run/etc/aiplayerbot.conf ]; then
    echo "aiplayerbot.conf already exists. Skipping..."
else
    echo "Copying aiplayerbot.conf..."
    cp $HOME_PATH/server/run/etc/aiplayerbot.conf.dist $HOME_PATH/server/run/etc/aiplayerbot.conf
fi
if [ -f $HOME_PATH/server/run/etc/ahbot.conf ]; then
    echo "ahbot.conf already exists. Skipping..."
else
    echo "Copying ahbot.conf..."
    cp $HOME_PATH/server/run/etc/ahbot.conf.dist $HOME_PATH/server/run/etc/ahbot.conf
fi

# Assuming client files are mounted at $HOME_PATH/client
echo "Extracting client data..."
CLIENT_PATH="$HOME_PATH/client"
EXTRACTION_OUTPUT="$HOME_PATH/server/client-data"
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
if [ "$(ls -A $EXTRACTION_OUTPUT)" ]; then
    echo "Client data already extracted. Skipping..."
else
    echo "Client data not extracted. Extracting..."
    # cp $HOME_PATH/server/run/bin/tools/ExtractResources.sh $HOME_PATH/server/run/bin/tools/MoveMapGen.sh $HOME_PATH/client/
    # ln -s $HOME_PATH/client/Data $HOME_PATH/server/run/bin/tools/Data
    # $HOME_PATH/client/ExtractResources.sh a $CLIENT_PATH $EXTRACTION_OUTPUT
    cd $HOME_PATH/server/run/bin/tools
    ./ExtractResources.sh a $CLIENT_PATH $EXTRACTION_OUTPUT
    echo "Client data extracted successfully."
fi

# Define the directories to check and move
DIRS=("maps" "dbc" "vmaps" "mmaps" "CreatureModels" "Cameras")

# Ensure the extracted data is moved to the correct directories
for DIR in "${DIRS[@]}"; do
    if [ -d "$HOME_PATH/server/run/bin/$DIR" ]; then
        echo "$DIR already copied to the correct directory. Skipping..."
    else
        if [ -d "$EXTRACTION_OUTPUT/$DIR" ]; then
            echo "Copying $DIR to the correct directory..."
            cp -r "$EXTRACTION_OUTPUT/$DIR" "$HOME_PATH/server/run/bin/$DIR"
            echo "$DIR moved successfully."
        else
            echo "$DIR does not exist in the extraction output. Skipping..."
        fi
    fi
done

# Copy mangosd.conf.dist and realmd.conf.dist to the etc directory
if [ -f $HOME_PATH/server/run/etc/mangosd.conf ]; then
    echo "mangosd.conf already exists. Skipping..."
else
    echo "Copying mangosd.conf..."
    cp $CORE_PATH/src/mangosd/mangosd.conf.dist.in $HOME_PATH/server/run/etc/mangosd.conf
    echo "mangosd.conf copied successfully."
fi

if [ -f $HOME_PATH/server/run/etc/realmd.conf ]; then
    echo "realmd.conf already exists. Skipping..."
else
    echo "Copying realmd.conf..."
    cp $CORE_PATH/src/realmd/realmd.conf.dist.in $HOME_PATH/server/run/etc/realmd.conf
    echo "realmd.conf copied successfully."
fi

# Start the CMaNGOS server
cd $HOME_PATH/server/run/bin

echo "Starting CMaNGOS server..."
screen -dmS mangosd ./mangosd -c $HOME_PATH/server/run/etc/mangosd.conf
echo "CMaNGOS server started in detached screen."

# Delete all default accounts and create new based on ADMIN_USERNAME and ADMIN_PASSWORD
if [[ $init_accounts = "true" ]]; then
    # Assuming mysql is the database client you are using

    # Generate and set random "passwords" for GAMEMASTER, MODERATOR, PLAYER
    for user in GAMEMASTER MODERATOR PLAYER; do
        # Generate a random password
        random_password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
        # Example hash calculation using SHA1 - You'll need to replace this with your actual method
        # The following is just a placeholder to demonstrate the approach:
        hashed_password=$(echo -n "$random_password" | sha1sum | awk '{print $1}')
        salt=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
        # Update the database - Assuming 'v' and 's' can directly take these hashed values
        mysql -umangos -pmangos -e "UPDATE classicrealmd.account SET v='$hashed_password', s='$salt' WHERE username='$user';"
    done
    echo "GAMEMASTER, MODERATOR, and PLAYER account passwords scrambled successfully."
    echo "###############################################################################################"
    echo "IMPORTANT! YOU MUST LOG IN AS ADMINISTRATOR/ADMINISTRATOR AND CHANGE ITS PASSWORD IMMEDIATELY!"
    echo "###############################################################################################"
fi

# Start the realmd service
echo "Starting realmd..."
./realmd -c $HOME_PATH/server/run/etc/realmd.conf &
echo "Realmd started successfully."

#Update website's config.php with the mysql information
CONFIG_PHP="$HOME_PATH/server/website/application/config.php"
sed -i "s/define('DB_HOST', '.*');/define('DB_HOST', '127.0.0.1');/" $CONFIG_PHP
sed -i "s/define('DB_USERNAME', '.*');/define('DB_USERNAME', 'root');/" $CONFIG_PHP
sed -i "s/define('DB_PASSWORD', '.*');/define('DB_PASSWORD', 'root');/" $CONFIG_PHP
sed -i "s/define('DB_REALMD', '.*');/define('DB_REALMD', 'classicrealmd');/" $CONFIG_PHP
sed -i "s/'mangosd_classic'/'classicmangos'/" $CONFIG_PHP
sed -i "s/'characters_classic'/'classiccharacters'/" $CONFIG_PHP
sed -i "s/define('WEBSITE_NAME', '.*');/define('WEBSITE_NAME', '$SERVER_NAME');/" $CONFIG_PHP
sed -i "s/define('WEBSITE_TIMEZONE', '.*');/define('WEBSITE_TIMEZONE', '${TIMEZONE//\//\\/}');/" $CONFIG_PHP

#If the website sql hasn't already been imported, make changes and import it. Check by seeing if the database exists
website_db_exists=$(mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -se "SHOW DATABASES LIKE 'website';")
#If the website database doesn't exist, import the website.sql
if [ "$website_db_exists" != "website" ]; then
    echo "Importing website.sql..."
    sed -i "s/<SERVER_NAME>/$SERVER_NAME/" $HOME_PATH/server/website/website.sql
    sed -i "s/<SERVER_ADDRESS>/$SERVER_ADDRESS/" $HOME_PATH/server/website/website.sql
    sed -i "s/<WEBSITE_PUBLIC_URL>/$WEBSITE_PUBLIC_URL/" $HOME_PATH/server/website/website.sql
    #Use current unix timestamp as the timestamp
    sed -i "s/<TIMESTAMP>/$(date +%s)/" $HOME_PATH/server/website/website.sql
    mysql -uroot -p"$MYSQL_ROOT_PASSWORD" < $HOME_PATH/server/website/website.sql
    #Import the website.sql using mysql
    mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE website;"
    mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON website.* TO 'mangos'@'localhost';"
    mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"
    mysql -umangos -pmangos website < $HOME_PATH/server/website/website.sql
    echo "website.sql imported successfully."
fi
#Update Website Announcement to replace placeholders


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
sudo cp -r $HOME_PATH/server/website/* /var/www/html 
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

# Prevent the container from exiting
tail -f /dev/null
