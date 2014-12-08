#!/bin/bash
#script to install a client machine for webServing benchmark. 
#Must be launched before backend and frontend server
#be careful, this bash will erase the current configuration of the machine
#works well on ubuntu 13.04 small instance

#exit if failed
set -e

#####  variables. Modify to your needs #####
PORT=3022
IP_CLIENT="10.50.6.XX"
JAVA_HOME="/usr/lib/jvm/java-6-openjdk-amd64"
DOWNLOAD_DIR=$HOME/Download

############### no need to modify under this line (normally) ##########################
######  prereq  #####
sudo apt-get install gcc -y
sudo apt-get install make -y
sudo apt-get install openjdk-6-jdk -y
sudo apt-get install ant -y

##check parameters
ssh -p $PORT $IP_CLIENT ls
cd $JAVA_HOME ; export JAVA_HOME=`pwd` ; echo JAVA_HOME=$JAVA_HOME > ~/.pam_environment


#Download the benchmark
mkdir -p $DOWNLOAD_DIR
cd $DOWNLOAD_DIR
echo "Downloading the benchmark from cloudSuite"
wget -c http://parsa.epfl.ch/cloudsuite/software/web.tar.gz ; tar xzvf web.tar.gz
##sources of API. By default, use the api from the downloaded benchmark. Modify if necessary
SOURCE_FABAN=$DOWNLOAD_DIR/web-release/faban-kit*
SOURCE_OLIO=$DOWNLOAD_DIR/web-release/apache-olio*
SOURCE_MYSQL=$DOWNLOAD_DIR/web-release/mysql-connector*


#####  installations  #####

#install faban
echo "Faban installation"
cd $HOME
tar zxvf $SOURCE_FABAN
cd faban; export FABAN_HOME=`pwd` ; echo FABAN_HOME=$FABAN_HOME >> ~/.pam_environment
echo "Faban successfully installed"

#install olio
echo "Apache Olio installation"
cd $HOME
tar zxvf $SOURCE_OLIO
cd apache-olio* ; export OLIO_HOME=`pwd` ; echo OLIO_HOME=$OLIO_HOME >> ~/.pam_environment
echo "Apache Olio successfully installed"

#install mysql-connector
echo "Mysql-connector unpacking"
cd $HOME
tar zxvf $SOURCE_MYSQL
cp mysql-connector-java-5.0.8/mysql-connector-java-5.0.8-bin.jar $OLIO_HOME/workload/php/trunk/lib
echo "Mysql-connector set up"

echo "configure faban"
cd $FABAN_HOME/
cp samples/services/ApacheHttpdService/build/ApacheHttpdService.jar services
cp samples/services/MysqlService/build/MySQLService.jar services
cp samples/services/MemcachedService/build/MemcachedService.jar services

echo "configure olio"
cd $OLIO_HOME/workload/php/trunk
cp build.properties.template build.properties

sed -i 's,faban\.home.*,faban.home='"$FABAN_HOME"',g' build.properties
sed -i 's,faban\.url.*,faban.url=http://'"$IP_CLIENT"':9980,g' build.properties

#build
echo "build with ant"
ant deploy.jar

#copy files to faban
cp $OLIO_HOME/workload/php/trunk/build/OlioDriver.jar $FABAN_HOME/benchmarks 

echo "start faban master"
$FABAN_HOME/master/bin/startup.sh
sleep 5
echo ""
echo "faban master is now installed."
echo "Fetching http://$IP_CLIENT:9980 to unpack OlioDriver.jar"
cd $DOWNLOAD_DIR
wget http://$IP_CLIENT:9980
rm -f index.html

if [ -d "$FABAN_HOME/benchmarks/OlioDriver" ]; then
echo "Installation completed ! please now install the backend server"
else 
echo "Fail to deploy Olio.jar. Please make sure port 9980 is open on that machine, then point your browser to  http://$IP_CLIENT:9980. You must see a welcoming message"
fi

exit 0
