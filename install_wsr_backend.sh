#!/bin/bash
#script to install a backend machine for webServing benchmark. 
#Must be launched after client machine
#be careful, this bash will erase the current configuration of the machine
#PLEASE be sure the keypair for scp is present on that machine before launch
#works well on ubuntu 13.04 small instance

#exit if failed
set -e

####   variables to adapt to your needs #####
KEYPAIR="/path/to/keypair"
IP_FRONTEND="10.50.6.XX"
HOST_CLIENT="ubuntu"
IP_CLIENT="10.50.6.XX"
DB_SERVER="10.50.6.XX"

LOAD_SCALE="100"

JAVA_HOME="/usr/lib/jvm/java-7-openjdk-amd64"
GEOCODER_HOME="$HOME/geocoder"
DOWNLOAD_DIR="$HOME/Download"

################## Don t modify under this line (normally) ##################

##check parameters
if [ ! -f $KEYPAIR ]; then echo "keypair does not exist"; exit 1; fi
ping -c1 $IP_FRONTEND
ping -c1 $IP_CLIENT
ping -c1 $DB_SERVER

cd $JAVA_HOME ; export JAVA_HOME=`pwd` ; echo JAVA_HOME=$JAVA_HOME_TMP > ~/.pam_environment

FABAN_HOME=`ssh -i $KEYPAIR $HOST_CLIENT@$IP_CLIENT 'echo $FABAN_HOME'` #retrieve faban home directory by ssh
OLIO_HOME=`ssh -i $KEYPAIR $HOST_CLIENT@$IP_CLIENT 'echo $OLIO_HOME'` #retrieve olio home directory by ssh


#####  prereq. Comment if not needed #####
sudo apt-get install gcc -y
sudo apt-get install make -y
sudo apt-get install java-common -y
sudo apt-get install ant -y
sudo apt-get install libaio1 -y

#scp of faban from client machine
echo "retrieve faban directory from client machine"
scp -r -i $KEYPAIR $HOST_CLIENT@$IP_CLIENT:$FABAN_HOME $FABAN_HOME
export FABAN_HOME=`pwd` ; echo FABAN_HOME=$FABAN_HOME_TMP >> ~/.pam_environment

#Download the benchmar
mkdir -p $DOWNLOAD_DIR
cd $DOWNLOAD_DIR
echo "Downloading the benchmark from cloudSuite"
wget http://parsa.epfl.ch/cloudsuite/software/web.tar.gz ; tar xzvf web.tar.gz
#sources of API. By default, use the api from the downloaded benchmark. Modify if necessary
SOURCE_MYSQL=$DOWNLOAD_DIR/web-release/mysql-5.5*
SOURCE_TOMCAT=$DOWNLOAD_DIR/web-release/apache-tomcat*


##### installations ###

#install mysql
echo -e "-------------\ninstalling mysql\n"
sudo groupadd mysql 
sudo useradd -r -g mysql mysql
cd $HOME
tar zxvf $SOURCE_MYSQL
MYSQL_HOME=$HOME/mysql*
sudo chown -R mysql $MYSQL_HOME
sudo chgrp -R mysql $MYSQL_HOME
cd $MYSQL_HOME
sudo cp support-files/my-medium.cnf /etc/my.cnf 
sudo scripts/mysql_install_db --user=mysql 
sudo bin/mysqld_safe --defaults-file=/etc/my.cnf --user=mysql & 
sleep 5
#mysql setup
echo -e "-------------\nsetting up olio database\n"
cd bin

echo "creating user olio" ; ./mysql -uroot -e "create user 'olio'@'%' identified by 'olio';"
echo "granting privileges" ; ./mysql -uroot -e "grant all privileges on *.* to 'olio'@'localhost' identified by 'olio' with grant option;"
./mysql -uroot -e "grant all privileges on *.* to 'olio'@'$IP_FRONTEND' identified by 'olio' with grant option;"
echo "creating database olio" ; ./mysql -uroot -e "create database olio;"
./mysql -uroot -e "use olio;"
./mysql -uroot -e "\. $FABAN_HOME/benchmarks/OlioDriver/bin/schema.sql"

echo "populate db"
cd $FABAN_HOME/benchmarks/OlioDriver/bin
chmod +x dbloader.sh
./dbloader.sh $DB_SERVER $LOAD_SCALE

#install tomcat
echo -e "-------------\nSetting up Tomcat\n"
tar zxvf $SOURCE_TOMCAT
cd apache-tomcat*
export CATALINA_HOME=`pwd` ; echo CATALINA_HOME=$CATALINA_HOME >> ~/.pam_environment
cd $CATALINA_HOME/bin
tar zxvf commons-daemon-native.tar.gz
cd commons-daemon-1.0.7-native-src/unix/
./configure
make
cp jsvc ../..

#install geocoder
echo -e "-------------\nSetting up Geocoder\n"
mkdir -p $GEOCODER_HOME 
export GEOCODER_HOME=$GEOCODER_HOME ; echo GEOCODER_HOME=$GEOCODER_HOME >> ~/.pam_environment
echo "retrive geocoder from client machine"
scp -r -i $KEYPAIR $HOST_CLIENT@$IP_CLIENT:$OLIO_HOME/geocoder $GEOCODER_HOME 

cd $GEOCODER_HOME/geocoder
cp build.properties.template build.properties
sed -i 's,^.*servlet\.lib\.path.*$,servlet.lib.path='"$CATALINA_HOME"'/lib'
echo "install with ant"
ant all

cp dist/geocoder.war $CATALINA_HOME/webapps

echo "start Tomcat"
$CATALINA_HOME/bin/startup.sh

echo "Installation successfull"
echo "please now install the frontend server in the third machine"
