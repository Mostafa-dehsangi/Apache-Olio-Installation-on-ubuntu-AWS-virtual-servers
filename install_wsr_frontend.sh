#!/bin/bash
#script to install a frontend machine for webServing benchmark. 
#Must be launched after client and backend machine
#be careful, this bash will erase the current configuration of the machine
#PLEASE be sure the keypair for scp is present on that machine before launch
#works well on ubuntu 13.04 small instance

#exit if failed
set -e

#####  prereq. Comment if not needed #####
sudo apt-get install gcc -y
sudo apt-get install make -y
sudo apt-get install openjdk-6-jdk -y
sudo apt-get install ant -y

####   variables to adapt to your needs #####
PORT=3022
IP_CLIENT="192.168.X.X"
IP_FRONTEND="192.168.Y.Y"
IP_BACKEND="192.168.Z.Z"
DB_SERVER="192.168.Z.Z"

FILESTORE="/filestore"
LOAD_SCALE=102 #rq if patch cloudsuite.patch is used, modifying this value is useless (see below)

JAVA_HOME="/usr/lib/jvm/java-6-openjdk-amd64"
DOWNLOAD_DIR="$HOME/Download"

################## Don t modify under this line (normally) ##################

##check parameters
ssh -p $PORT $IP_CLIENT ls
ssh -p $PORT $IP_FRONTEND ls
ssh -p $PORT $IP_BACKEND ls
ssh -p $PORT $DB_SERVER ls

cd $JAVA_HOME ; export JAVA_HOME=`pwd` ; echo JAVA_HOME=$JAVA_HOME > ~/.pam_environment

#check free space
echo "checking space"
if [ `df | grep "/$" | awk '{print $4}'` -ge 20000000 ]; then 
  echo "enough space. Continuing"
else 
  echo "Space not enough. This benchmark request at least 10G of free memory. Please choose a bigger instance or check your logical partitions"
  exit 1
fi


FABAN_HOME=`ssh -p $PORT $IP_CLIENT 'echo $FABAN_HOME'` #retrieve faban home directory by ssh

#scp of faban from client machine
echo ">> retrieve faban directory from client machine"
scp -P $PORT -r $IP_CLIENT:$FABAN_HOME $FABAN_HOME
cd $FABAN_HOME
export FABAN_HOME=`pwd` ; echo FABAN_HOME=$FABAN_HOME >> ~/.pam_environment
########
#Download the benchmark
mkdir -p $DOWNLOAD_DIR
cd $DOWNLOAD_DIR
echo ">> Downloading the benchmark from cloudSuite"
wget -c http://parsa.epfl.ch/cloudsuite/software/web.tar.gz ; tar xzvf web.tar.gz
#sources of API. By default, use the api from the downloaded benchmark. Modify if necessary
SOURCE_OLIO=$DOWNLOAD_DIR/web-release/apache-olio*
SOURCE_NGINX=$DOWNLOAD_DIR/web-release/nginx*
SOURCE_MYSQL=$DOWNLOAD_DIR/web-release/mysql-5.5*
SOURCE_PHP=$DOWNLOAD_DIR/web-release/php*
SOURCE_PATCH=$DOWNLOAD_DIR/web-release
SOURCE_APC=$DOWNLOAD_DIR/web-release/APC*

##### installations ###

#install webapp
sudo mkdir -p /var/www
cd /var/www
export APP_DIR=`pwd` ; echo APP_DIR=$APP_DIR >> ~/.pam_environment

echo -e ">> -------------\ninstalling olio\n"
cd $HOME
tar zxvfk $SOURCE_OLIO #k to avoid untar if file already exists
cd apache-olio*
export OLIO_HOME=`pwd` ; echo OLIO_HOME=$OLIO_HOME >> ~/.pam_environment
sudo cp -r $OLIO_HOME/webapp/php/trunk/* $APP_DIR
sudo cp $SOURCE_PATCH/cloudstone.patch $APP_DIR
cd $APP_DIR
sudo patch -p1 < cloudstone.patch 

#defining variable of config
cd $APP_DIR/etc/
export PHPRC=`pwd` ; echo PHPRC=$PHPRC >> ~/.pam_environment

echo ">> config de olio"
sudo sed -i 's,^$olioconfig\['\''dbTarget'\''\].*$,$olioconfig\['\''dbTarget'\''\] = '\''mysql:host='$DB_SERVER';dbname=olio'\'';,g' $PHPRC/config.php
sudo sed -i 's,$olioconfig\['\''cacheSystem'\''\] = '\''MemCached'\'',$olioconfig\['\''cacheSystem'\''\] = '\''NoCache'\'',g' $PHPRC/config.php

sudo sed -i 's,^.*$olioconfig\['\''geocoderURL'\''\].*$,$olioconfig\['\''geocoderURL'\''\] = '\''http://'$IP_BACKEND':8080/geocoder/geocode'\'';,g' $PHPRC/config.php


#Nginx
echo -e ">> -------------\ninstalling nginx\n"
sudo apt-get install libpcre3 libpcre3-dev libpcrecpp0 libssl-dev zlib1g-dev -y
cd $HOME
tar zxvfk $SOURCE_NGINX
cd nginx*
./configure
make
sudo make install

sudo /usr/local/nginx/sbin/nginx
sleep 5
wget http://$IP_FRONTEND
sudo /usr/local/nginx/sbin/nginx -s stop

export CONF_NGINX=/usr/local/nginx/conf/nginx.conf

echo ">> Modif de location /"
sudo sed -i '/^[ ]*location \//,/}/s!root.*$!root '"$APP_DIR"'/public_html;!g' "$CONF_NGINX"
sudo sed -i '/^[ ]*location \//,/}/s!\(index.*\);$!\1 index.php;!g' "$CONF_NGINX"

echo ">> decommenter PHP-FPM"
sudo sed -i '/fastcgi/I,/}/s!#\(.*[;{}].*\)!\1!g' "$CONF_NGINX"

echo ">> Modif de fastcgi"
sudo sed -i 's!\(^[ ]*fastcgi_param\).*$!\1 SCRIPT_FILENAME  '"$APP_DIR"'/public_html/$fastcgi_script_name;!g' "$CONF_NGINX"
sudo sed -i '/fastcgi/I,/}/s!root.*$!root '"$APP_DIR"'/public_html;!g' "$CONF_NGINX"

echo ">> Access log off"
sudo sed -i '/server/,/}/N;s/^[ ]*server[ ]*{\n\([ ]*\)/&access_log off;\n\1/g' "$CONF_NGINX"

echo ">> start the nginx server"
sudo /usr/local/nginx/sbin/nginx

#php
echo -e ">> -------------\ninstalling php\n"
cd $HOME

sudo apt-get install libxml2-dev curl libcurl3 libcurl3-dev libjpeg-dev libpng-dev -y

echo ">> untar mysql"
tar zxvfk $SOURCE_MYSQL
cd mysql-5.5*
export MYSQL_HOME=`pwd` ; echo MYSQL_HOME=$MYSQL_HOME >> ~/.pam_environment

echo ">> untar php"
cd $HOME
tar zxvfk $SOURCE_PHP
cd php*

export PHP_CONFIG=/usr/local/bin/php-config

echo ">> patch from internet. If wget does'nt work, see downloaded patch in the repository of this install"
wget https://mail.gnome.org/archives/xml/2012-August/txtbgxGXAvz4N.txt
mv txtbgxGXAvz4N.txt php-5.3.9-libxm2-2.9.0.patch
patch -p0 < php-5.3.9-libxm2-2.9.0.patch

echo ">> installation"
./configure --enable-fpm --with-curl --with-pdo-mysql=$MYSQL_HOME --with-gd --with-jpeg-dir --with-png-dir --with-config-file-path=$PHPRC
make
sudo make install

sudo mkdir -p /tmp/http_sessions

echo ">> configure php"
sudo sed -i '/^;.*extension/s!$!\nextension_dir=/usr/local/lib/php/extensions/no-debug-non-zts-20090626/!' $PHPRC/php.ini
sudo sh -c 'echo date.timezone = \"Asia/Shanghai\" >> /var/www/etc/php.ini'
sudo sed -i 's!^.*error_reporting.*$!error_reporting = E_ALL \& ~E_NOTICE ; or error_reporting = E_NONE\ndisplay_errors = Off!g' $PHPRC/php.ini

echo ">> start pfp-fpm"
sudo cp /usr/local/etc/php-fpm.conf.default /usr/local/etc/php-fpm.conf
sudo addgroup nobody #a modifier pour la reprise sur erreur
sudo /usr/local/sbin/php-fpm

#APC
cd $HOME
echo -e ">> -------------\ninstalling APC\n"
sudo apt-get install autoconf -y

tar zxvfk $SOURCE_APC
cd APC*
phpize
./configure --enable-apc --enable-apc-mmap --with-php-config=$PHP_CONFIG
make
sudo make install
sudo killall php-fpm

echo ">> running php-fpm"
sudo /usr/local/sbin/php-fpm
sleep 5
php-fpm -m | grep apc #apc must be present

#FILESTORE
echo -e ">> -------------\ninstalling filestore\n"

sudo cp $SOURCE_PATCH/cloudsuite.patch $APP_DIR
cd $APP_DIR
sudo patch -p1 < cloudsuite.patch ; LOAD_SCALE=102 #if patch is used, load scale must be set to 102, regardless of DB

sudo mkdir -p $FILESTORE
cd $FILESTORE
export FILESTORE=`pwd` ; echo FILESTORE=$FILESTORE >> ~/.pam_environment
sudo chmod a+rwx $FILESTORE
chmod +x $FABAN_HOME/benchmarks/OlioDriver/bin/fileloader.sh

echo ">> populating filestore"
$FABAN_HOME/benchmarks/OlioDriver/bin/fileloader.sh $LOAD_SCALE $FILESTORE 

sudo sed -i 's,^$olioconfig\['\''localfsRoot'\''\].*$,$olioconfig\['\''localfsRoot'\''\] = '\'"$FILESTORE"\'';,g' $PHPRC/config.php

echo ">> restart PHP-FPM"

sudo killall php-fpm
sudo /usr/local/sbin/php-fpm

echo "installation succeeded. You can now run the benchmark pointing your browser to http://$IP_CLIENT:9980"

