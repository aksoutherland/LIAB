#!/bin/bash

# Absolute path to the 'pub' directory for the FTP server
FTPDIR=/var/ftp/pub

SHORTHUMANNAME="CentOS v6.7"
# Here 'DVD' is meant to differentiate between the ISO we want and the 8GB 'Everything' ISO
LONGHUMANNAME="CentOS Linux v6.7 DVD"
ISO=CentOS-6.7-x86_64-bin-DVD1.iso
# Official public primary sources.  Note that which of these URLs work will change over time
# as v6.7 is replaced by v6.8 and gets 'demoted'.
ISOURL[0]="http://vault.centos.org/6.7/isos/x86_64/CentOS-6.7-x86_64-bin-DVD1.iso"
ISOURLalt[0]="http://108.61.16.227/6.7/isos/x86_64/CentOS-6.7-x86_64-bin-DVD1.iso"
ISOURL[1]="http://centos.mirrors.tds.net/pub/linux/centos/6.7/isos/x86_64/CentOS-6.7-x86_64-bin-DVD1.iso"
ISOURL[2]="http://archive.kernel.org/centos-vault/6.7/isos/x86_64/CentOS-6.7-x86_64-bin-DVD1.iso"
# OKC EERC.  Run by Daniel_Johnson1.
ISOURL[3]="http://dyson.okc.eerclab.dell.com/m/hb/Distros/centos/partners.centos.com/6.7/isos/x86_64/CentOS-6.7-x86_64-bin-DVD1.iso"
ISOURLalt[3]="http://10.14.176.76/m/hb/Distros/centos/partners.centos.com/6.7/isos/x86_64/CentOS-6.7-x86_64-bin-DVD1.iso"
ISOURL[4]="http://dyson.okc.eerclab.dell.com/fs/Lab/OSISO/Linux/CentOS/6.7/x86_64/CentOS-6.7-x86_64-bin-DVD1.iso"
ISOURLalt[4]="http://10.14.176.76/fs/Lab/OSISO/Linux/CentOS/6.7/x86_64/CentOS-6.7-x86_64-bin-DVD1.iso"
# RR EERC.  Run by Keith_Wier.
ISOURL[5]="http://file1.eerc.local/SoftLib/ISOs/Linux/CentOS/6.7/CentOS-6.7-x86_64-bin-DVD1.iso"
ISOURLalt[5]="http://10.180.48.120/SoftLib/ISOs/Linux/CentOS/6.7/CentOS-6.7-x86_64-bin-DVD1.iso"
ISOSIZE=3895459840
ISOSHA256=c0c1a05d3d74fb093c6232003da4b22b0680f59d3b2fa2cb7da736bc40b3f2c5
ISO_HEAD_20MB_MD5=4b85a640d2fc89ef2ce54f24145a7dce
# Mount point relative to the FTP root, used in some URLs
ISOMOUNTDIRREL="centos-6.7/dvd"
ISOMOUNTDIR="${FTPDIR}/${ISOMOUNTDIRREL}"
ISOMOUNTVERIFY="CentOS_BuildTag"

# Get a temporary directory
CSTD=`mktemp -d`

#create a folder to mount the ISO to, copy the iso to the FTP folder
mkdir -p "${ISOMOUNTDIR}"

#for the next command to work, cent.iso must exist in root's home folder
mv /root/cent.iso "${ISOMOUNTDIR}"

#add a line to fstab to mount the iso at boot
echo "/var/ftp/pub/centos-6.7.iso  /var/ftp/pub/centos-6.7/dvd  auto  ro,loop,context=system_u:object_r:public_content_t:s0  1 0" >> /etc/fstab

#this command will mount the iso during the script so that later on we can copy files from the iso
mount -a 

#modify XPE default config file 
cat >/var/lib/tftpboot/pxelinux.cfg/default <<EOF
display f1.msg
prompt 1
timeout 300
default quit

label quit
  localboot 0

label centos7
  kernel centos-7.0/vmlinuz
  append initrd=centos-7.0/initrd.img root=live:http://server1.example.com/pub/centos-7.0/dvd/LiveOS/squashfs.img repo=http://server1.example.com/pub/centos-7.0/dvd/ noipv6 ks=http://server1.example.com/pub/station_ks.cfg

label centos6
  kernel centos-6.7/vmlinuz
  append initrd=centos-6.7/initrd.img noipv6 ks=http://server1.example.com/pub/station1_ks.cfg
EOF

#modify the PXE boot menu prompt
cat >/var/lib/tftpboot/f1.msg <<EOF
pxe boot menu

type this : to do this
quit      : boot the local hard drive
centos7   : install centos-7.0
centos6   : install centos-6.7
EOF

#create the folder where the needed boot files will live and then populate the folder with the required files this requires successful mounting of the iso in a previous step

mkdir /var/lib/tftpboot/centos-6.7
cp /var/ftp/pub/centos-6.7/dvd/isolinux/TRANS.TBL /var/lib/tftpboot/centos-6.7/
cp /var/ftp/pub/centos-6.7/dvd/isolinux/vmlinuz /var/lib/tftpboot/centos-6.7/
cp /var/ftp/pub/centos-6.7/dvd/isolinux/initrd.img /var/lib/tftpboot/centos-6.7/

#create the kickstart file
cat > /var/www/html/pub/station_ks_0_5_13.cfg <<EOF
install
url --url=http://server1/pub/centos-6.7/dvd
lang en_US.UTF-8
keyboard us
network --onboot yes --device eth0 --bootproto dhcp --noipv6

rootpw password

user --name=student1 --password=password
user --name=student2 --password=password
user --name=student3 --password=password
user --name=student4 --password=password
user --name=student5 --password=password
user --name=deleteme --password=deleteme

firewall --service=ssh
authconfig --enableshadow --passalgo=sha512
selinux --enforcing
timezone --utc America/Chicago
bootloader --location=mbr --driveorder=sda --append="crashkernel=auto rhgb quiet"

ignoredisk --only-use=sda
zerombr
clearpart --linux --initlabel

part /boot --fstype=ext4 --size=500
part pv.008002 --grow --size=1

volgroup VolGroup --pesize=4096 pv.008002
logvol / --fstype=ext4 --name=lv_root --vgname=VolGroup --grow --size=1024 --maxsize=51200
logvol swap --name=lv_swap --vgname=VolGroup --grow --size=1008 --maxsize=2016

repo --name="Red Hat Enterprise Linux"  --baseurl=http://server1/pub/centos-6.7/dvd/ --cost=100
reboot

%packages
@base
@client-mgmt-tools
@core
@debugging
@basic-desktop
@desktop-debugging
@desktop-platform
@directory-client
@fonts
@general-desktop
@graphical-admin-tools
@input-methods
@internet-browser
@java-platform
@legacy-x
@network-file-system-client
@perl-runtime
@print-client
@remote-desktop-clients
@server-platform
@server-policy
@x11
mtools
pax
python-dmidecode
oddjob
sgpio
genisoimage
wodim
abrt-gui
certmonger
pam_krb5
krb5-workstation
libXmu
perl-DBD-SQLite
%end

%post
#(
#if dmidecode|grep -q "Product Name: VMware Virtual Platform"
#then
#	cd /tmp
#	wget http://server1/pub/materials/VMwareTools.tar.gz
#	tar xzvf VMwareTools.tar.gz
#	cd vmware-tools-distrib
#	./vmware-install.pl default
#fi

############################################################
# /etc/kickstart-release
############################################################
rm /etc/yum.repos.d/*
chkconfig NetworkManager off
chkconfig firstboot off

mkdir -m 700 -p /root/.ssh
wget -q -O - http://server1/pub/materials/id_rsa.pub >>/root/.ssh/authorized_keys

restorecon -R /root/.ssh
chmod 600 /root/.ssh/authorized_keys
wget -q -O /etc/yum.repos.d/centos-6.7.repo http://server1/pub/materials/centos-6.7.repo

#echo "UseDNS no" >>/etc/ssh/sshd_config

echo "default web url" > /root/default.html
echo "welcome to vhost" > /root/vhost.html
sed -i -e s/id:.:initdefault:/id:3:initdefault:/ /etc/inittab

#wget -q -O /etc/hosts http://server1/pub/hosts

wget -q -O /root/user-script.sh http://server1/pub/materials/user-script.sh

chmod 200 /root/user-script.sh

dd if=/dev/zero of=/dev/sdb bs=512 count=1
dd if=/dev/zero of=/dev/sdc bs=512 count=1
dd if=/dev/zero of=/dev/sdd bs=512 count=1
dd if=/dev/zero of=/dev/sde bs=512 count=1

echo 'logger "aliens are among us"' >> /etc/rc.local
mkdir /home/student{1..5}/files
touch /home/student{1..5}/files/file{1..15}.txt
for i in /home/student*/files/*.txt; do echo "big brother is watching" >> $i; done
groupadd deletethisgroup

) 2>&1 | tee /root/install.log | tee /dev/console
EOF

#here we make a symlink the kickstart file to a file with a friendlier name
ln -s /var/www/html/pub/station_ks_0_5_13.cfg /var/www/html/pub/station1_ks.cfg

#here we a creating a repo file for the centos6 stations to use
cat > /var/www/html/pub/materials/centos-6.7.repo <<EOF

[server1]
name=CentOS 6.7
baseurl=ftp://server1/pub/centos-6.7/dvd/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6

[plusrepo]
name=Additional Packages
baseurl=ftp://server1/pub/plusrepo
enabled=0
gpgcheck=0
EOF