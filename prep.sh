#!/bin/bash
#we are going to setup some variables to clean up the output a bit
PITD=`mktemp -d`
LOG="${PITD}/postinstall.log"
#lets create a copy of the iso to use in the environemt
echo " " 
echo "Please ensure that your CentOS Linux Installation ISO is attached to your VM!"
echo " " 
echo "Creating copy of your ISO, please be patient as this will take a few minutes!"
cp /dev/sr0 /root/centos.iso
#added a check to ensure the iso is really attached
ret_code=$?
if [[ $ret_code -ne 0 ]]; then
  echo " "
  echo "Failed to copy ISO! Please ensure that your Installation ISO is attached to your VM!"
  exit $ret_code
fi
echo " " 
echo "Installation Media ISO created successfully!"
echo " " 
echo "Setting up PostInstall Script Environment"
#these commands set centos to use vault.centos.org because centos mirrorlist has been removed
sed -i -e "s|mirrorlist=|#mirrorlist=|g" /etc/yum.repos.d/CentOS-*
sed -i -e "s|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g" /etc/yum.repos.d/CentOS-*
#this command will install git on the server
yum install -y git &>>"${LOG}"
#this command will give us a temporary working directory
OUT="$(mktemp -d /run/tmp.XXX)"
cd $OUT
#this command will clone the LIAB repo to the local machine 
git clone https://github.com/aksoutherland/LIAB &>>"${LOG}"
echo " " 
echo "Beginning Post Install Script"
#this command will kickoff the postinstall script
$OUT/LIAB/postinstall.sh

