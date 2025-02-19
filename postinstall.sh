#!/bin/bash
BL1="Linux In A Box lab server, PostInstall configuration"
BL2="2021-09-04 for CentOS Linux 8.2                     "
BL3="                                                    "
BL4="                                                    "
KICKSTARTRELEASE="Linux server1 kickstart v3.1"
echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"

echo ""
echo "${BL1}"; echo "${BL2}"; echo "${BL3}"; echo "${BL4}"
echo "" 
echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"

FTPDIR=/var/ftp/pub
PITD=`mktemp -d`
LOG="${PITD}/postinstall.log"

am_I_sourced () {
  # From  http://stackoverflow.com/a/12396228
  if [ "${FUNCNAME[1]}" = source ]; then
    #echo "I am being sourced, this filename is ${BASH_SOURCE[0]} and my caller script/shell name was $0"
    return 0
  else
    #echo "I am not being sourced, my script/shell name was $0"
    return 1
  fi
}

if am_I_sourced ; then
  echo "ERROR: This script must be called directly rather than being 'sourced'."
  # See, can't use 'exit' here
  return 0
fi

[ 0 -ne $UID ] && echo "ERROR: This MUST be run as root!  Try again." && exit 1
if am_I_sourced ; then
  MPOINT=`dirname ${BASH_SOURCE[0]}`
else
  MPOINT=`dirname $0`
fi
[ "/" != "${MPOINT:0:1}" ] && echo "ERROR: You must call this script using an absolute path, not a relative path." && echo "       Example:  /mnt/postinstall.sh" && exit 1
pwd | grep -q "^${MPOINT}" && echo "ERROR: You must NOT call this script from the mount point directory itself." && echo "       Use something like    cd /root; ${0}" && exit 1
CDDEVICE=`mount | grep "$MPOINT" | head -n 1 | cut -d " " -f 1`

VERIFYCHECKSUM=1
APPLYUPDATES=1
INSTALLRPMS=1
	# 2015-04-27  VMware Tools isn't _really_ needed, and I'm running into some
	# problems with it making scripts hang.  For now, skipping it.
INSTALLVMTOOLS=0
DONORMALCONFIG=1
DOLDAPCONFIG=1
DOKERBEROSCONFIG=1
SKIPOSCHECK=0
NUMOFWS=11

DETECTEDOS=99
#the next 3 lines are not needed since we are working only with CentOS8
#grep -q "^CentOS Linux release 7.0.1406 (Core)" /etc/redhat-release && DETECTEDOS=10
#grep -q "^CentOS Linux release 7.1.1503 (Core)" /etc/redhat-release && DETECTEDOS=11
#grep -q "^CentOS Linux release 7.2.1511 (Core)" /etc/redhat-release && DETECTEDOS=12
grep -q "^CentOS Linux release 8.2.2004 (Core)" /etc/redhat-release && DETECTEDOS=13

popd &>/dev/null

[ -d ${FTPDIR}/ ] || mkdir -p ${FTPDIR}/

echo ""
`echo "bG9nZ2VyIFRoaXMgd2FzIGEgdHJpdW1waC4K" | base64 -d`
echo ""
echo "Passed sanity checks, now we deploy and use the setup magic."
echo ""


(echo "${BL1}"; echo "${BL2}"; echo "${BL3}"; echo "${BL4}")  >>"${LOG}"
echo "${KICKSTARTRELEASE}" > /etc/kickstart-release

cp -af ${MPOINT}/ftppub/* ${FTPDIR}/
cp -f ${MPOINT}/breakme /usr/local/sbin/
cp -f ${MPOINT}/scrape_dhcp_settings.sh /usr/local/sbin/scrape_dhcp_settings.sh
chmod 555 /usr/local/sbin/breakme
chmod 555 /usr/local/sbin/scrape_dhcp_settings.sh

###############################################################################################

network_config() {
echo " " 
echo "Starting Network Config"
echo " " 
nmcli -t -f DEVICE,TYPE,CONNECTION,CON-UUID device | grep "ethernet" > ${PITD}/NICs
NUM_OF_NICS=`wc -l < ${PITD}/NICs`
let NUM_OF_NICS+=0
if [ 2 -gt ${NUM_OF_NICS} ]; then
  echo "ERROR: There are not enough Ethernet NICs available.  Ensure you have 2 and" | tee -a "${LOG}"
  echo "       try again." | tee -a "${LOG}"
  exit 1
fi
if [ 2 -lt ${NUM_OF_NICS} ]; then
  echo "I only need two Ethernet NICs, but you have ${NUM_OF_NICS}.  That's OK," | tee -a "${LOG}"
  echo "I'll just use the first two.  You can do what you want with the rest." | tee -a "${LOG}"
fi

NIC1NAME=`head -n 1 < ${PITD}/NICs | cut -d ":" -f 1`
NIC1CON=`head -n 1 < ${PITD}/NICs | cut -d ":" -f 3`
NIC1CONUUID=`head -n 1 < ${PITD}/NICs | cut -d ":" -f 4`
NIC2NAME=`head -n 2 < ${PITD}/NICs | tail -n 1 | cut -d ":" -f 1`
NIC2CON=`head -n 2 < ${PITD}/NICs | tail -n 1 | cut -d ":" -f 3`
NIC2CONUUID=`head -n 2 < ${PITD}/NICs | tail -n 1 | cut -d ":" -f 4`

# Configure NetworkManager use dhclient
echo "Create /etc/NetworkManager/conf.d/dhclient.conf" &>>"${LOG}"
cat > /etc/NetworkManager/conf.d/dhclient.conf << EOF
[main]
dhcp=dhclient
EOF
echo "systemctl restart NetworkManager" &>>"${LOG}"
systemctl restart NetworkManager &>>"${LOG}"

if [ "${NIC1CON}" != "External" ]; then
  echo "nmcli device disconnect ${NIC1NAME}" &>>"${LOG}"
  nmcli device disconnect ${NIC1NAME} &>>"${LOG}"
  if [ "${NIC1CONUUID}" != "--" ]; then
    # If the connection name/UUID is '--' then it was blank/not set.
	echo "nmcli connection delete uuid ${NIC1CONUUID}" &>>"${LOG}"
    nmcli connection delete uuid ${NIC1CONUUID} &>>"${LOG}"
  fi
  
  # "DHCP" is implied when you don't specify an IP address.  In fact I see no way
  # to explicitly state DHCP as an option...?
  echo "nmcli connection delete id ${NIC1NAME}" &>>"${LOG}"
  nmcli connection delete id ${NIC1NAME} &>>"${LOG}"
  echo "nmcli connection add type ethernet con-name External ifname ${NIC1NAME}" &>>"${LOG}"
  nmcli connection add type ethernet con-name External ifname ${NIC1NAME} &>>"${LOG}"
  echo "nmcli connection modify External connection.zone \"external\" ipv4.dns-search \"example.com\"" &>>"${LOG}"
  # I removed the ipv4.ignore-auto-dns option so that it would pickup the DNS servers from DHCP
  nmcli connection modify External connection.zone "external" ipv4.dns-search "example.com" &>>"${LOG}"
  # To ensure that our just-modified settings for DNS are used, briefly re-drop the connection
  echo "nmcli device disconnect ${NIC1NAME}" &>>"${LOG}"
  nmcli device disconnect ${NIC1NAME} &>>"${LOG}"
  sleep 2
  echo "nmcli device connect ${NIC1NAME}" &>>"${LOG}"
  nmcli device connect ${NIC1NAME} &>>"${LOG}"
  # And give it time to find an address.
  sleep 2
  echo "NIC1 (${NIC1NAME}) configured for DHCP operation.  Current address (if any):" | tee -a "${LOG}"
else
  echo "The first NIC (${NIC1NAME}) looks like it was already configured.  To" | tee -a "${LOG}"
  echo "avoid changing anything that you've customized, I'll leave it alone." | tee -a "${LOG}"
  echo "Current address (if any):" | tee -a "${LOG}"
fi
ip address show ${NIC1NAME} | grep "inet" | cut -d " " -f 1-6 | tee -a "${LOG}"


echo "nmcli device disconnect ${NIC2NAME}" &>>"${LOG}"
nmcli device disconnect ${NIC2NAME} &>>"${LOG}"
if [ "${NIC2CONUUID}" != "--" ]; then
  # If the connection name/UUID is '--' then it was blank/not set.
  echo "nmcli connection delete uuid ${NIC2CONUUID}" &>>"${LOG}"
  nmcli connection delete uuid ${NIC2CONUUID} &>>"${LOG}"
fi
echo "nmcli connection delete id ${NIC2NAME}" &>>"${LOG}"
nmcli connection delete id ${NIC2NAME} &>>"${LOG}"
echo "nmcli connection delete id Internal" &>>"${LOG}"
nmcli connection delete id Internal &>>"${LOG}"
echo "nmcli connection add type ethernet con-name Internal ifname ${NIC2NAME} ip4 172.26.0.1/24 ip6 fd07:de11:2015:0324::1/64" &>>"${LOG}"
nmcli connection add type ethernet con-name Internal ifname ${NIC2NAME} ip4 172.26.0.1/24 ip6 fd07:de11:2015:0324::1/64 &>>"${LOG}"
echo "nmcli connection modify Internal connection.zone \"internal\" ipv4.dns \"127.0.0.1\" ipv4.dns-search \"example.com\"" &>>"${LOG}"
nmcli connection modify Internal connection.zone "internal" ipv4.dns "127.0.0.1" ipv4.dns-search "example.com" &>>"${LOG}"
echo "nmcli device disconnect ${NIC2NAME}" &>>"${LOG}"
nmcli device disconnect ${NIC2NAME} &>>"${LOG}"
sleep 2
echo "nmcli device connect ${NIC2NAME}" &>>"${LOG}"
nmcli device connect ${NIC2NAME} &>>"${LOG}"
sleep 2
echo "NIC2 (${NIC2NAME}) configured with static addresses"  | tee -a "${LOG}"
ip address show ${NIC2NAME} | grep "inet" | cut -d " " -f 1-6 | tee -a "${LOG}"
echo ""  | tee -a "${LOG}"
ip address show  &>>"${PITD}/ip_a_s.txt"
nmcli connection &>>"${PITD}/nmcli_con.txt"
nmcli device &>>"${PITD}/nmcli_dev.txt"
ethtool ${NIC1NAME} &>>"${PITD}/ethtool_1.txt"
ethtool ${NIC2NAME} &>>"${PITD}/ethtool_2.txt"

/usr/local/sbin/scrape_dhcp_settings.sh phase1_temp &>/dev/null

[ ! -f /etc/hosts_orig ] && cp -a /etc/hosts /etc/hosts_orig || cp -a /etc/hosts_orig /etc/hosts
echo "172.26.0.1  server1.example.com  server1" >> /etc/hosts
echo "172.26.0.1  server1.registry.example.com  registry" >> /etc/hosts
echo "server1.example.com" > /etc/hostname
hostname server1

timedatectl set-timezone America/Chicago
echo " " 
echo "End Network Config"
}

######################################################################################################

package_installation() {
echo " "
echo " "
echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
echo " "
echo " "
ISO=CentOS8.2.iso
# Removing the dd and doing this with a hardlink instead
ln /root/centos.iso ${FTPDIR}/${ISO} &>>"${LOG}"
ISOMOUNTDIRREL="centos-8.2/dvd"
ISOMOUNTDIR="${FTPDIR}/${ISOMOUNTDIRREL}"
mkdir -p "${FTPDIR}/${ISOMOUNTDIRREL}"
sed --in-place "/${ISO}/d" /etc/fstab &>/dev/null
echo "${FTPDIR}/${ISO}  ${ISOMOUNTDIR}  auto  ro,loop,context=system_u:object_r:public_content_t:s0  1 0" >> /etc/fstab
rm -rf ${ISOMOUNTDIR} &>/dev/null
mkdir -p ${ISOMOUNTDIR} &>/dev/null
restorecon -R ${ISOMOUNTDIR} ${FTPDIR}/${ISO}*
mount ${ISOMOUNTDIR}  >>  "${LOG}"

echo "Starting Package Installation, Please be patient as this may take a while."
echo " " 
echo " " 
echo "Applying pre-install OS updates." | tee -a "${LOG}"
echo " " 
  yum -y update >"${PITD}/yum_update.txt" &>> "${LOG}"

echo "Patching repositories to point to vault.centos.org" &>> "${LOG}"

sed -i -e "s|mirrorlist=|#mirrorlist=|g" /etc/yum.repos.d/CentOS-*
sed -i -e "s|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g" /etc/yum.repos.d/CentOS-*

echo " " 
echo "Updates complete, moving on to Package Installation" | tee -a "${LOG}"  
echo " " 
  yum install -y epel-release >> "${PITD}/yum_update.txt" &>>"${LOG}"
echo " " 
echo " " 
echo "Package installation in progress..." | tee -a "${LOG}"
echo " " 
echo " " 
  yum -y install "@Network Servers" "@System Tools" "@Server" spax dmidecode oddjob sgpio \
    certmonger krb5-server krb5-server-ldap sssd-krb5-common krb5-workstation \
    perl-DBD-SQLite httpd vsftpd nfs-utils nfs4-acl-tools dhcp-server dhcp-common tftp tftp-server \
    bind-chroot bind-utils createrepo openldap openldap-devel openldap-clients ypserv \
    selinux-policy-targeted python3-policycoreutils syslinux iscsi-initiator-utils ftp lftp samba-client samba* unzip zip lsof \
    mlocate targetcli tcpdump pykickstart chrony net-tools patch rng-tools open-vm-tools rsync \
    policycoreutils-devel sos xinetd vim bash-completion sl &>"${PITD}/yum_install.txt"
  echo >>"${PITD}/yum_install.txt"
  echo "Package Installation Complete." | tee -a "${LOG}"
echo ""
}

############################################################################################

misc1_config() {
	
echo "Setting up general stuff." | tee -a "${LOG}"
echo "   Configuring Lab Setup Magic" | tee -a "${LOG}"

cat /etc/kickstart-release >>/etc/issue

systemctl enable rngd.service &>>"${LOG}"
systemctl start rngd.service  &>>"${LOG}"

echo "   Configuring Lab Routes" | tee -a "${LOG}"
for i in `seq 1 9`; do
  echo "172.26.$i.0/24 via 172.26.0.20$i dev ${NIC2NAME}" >>/etc/sysconfig/network-scripts/route-Internal
done
for i in `seq 10 ${NUMOFWS}`; do
  echo "172.26.$i.0/24 via 172.26.0.2$i dev ${NIC2NAME}" >>/etc/sysconfig/network-scripts/route-Internal
done

echo "   Configuring Web Service" | tee -a "${LOG}"
cd /var/www/html
ln -s ${FTPDIR}
systemctl enable httpd.service &>>"${LOG}"
systemctl start httpd.service &>>"${LOG}"

echo "   Configuring FTP Service" | tee -a "${LOG}"

cat >/etc/vsftpd/vsftpd.conf <<EOF
anonymous_enable=YES
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
xferlog_std_format=YES
listen=NO
listen_ipv6=YES
pam_service_name=vsftpd
userlist_enable=YES
EOF

systemctl enable vsftpd.service &>>"${LOG}"
systemctl start vsftpd.service &>>"${LOG}"

# adding this section in to ensure dns works properly before we configure and enable DNS
  nmcli connection modify External connection.zone "external" ipv4.ignore-auto-dns "true" ipv4.dns "127.0.0.1" ipv4.dns-search "example.com" &>>"${LOG}"
  # To ensure that our just-modified settings for DNS are used, briefly re-drop the connection
  echo "nmcli device disconnect ${NIC1NAME}" &>>"${LOG}"
  nmcli device disconnect ${NIC1NAME} &>>"${LOG}"
  sleep 2
  echo "nmcli device connect ${NIC1NAME}" &>>"${LOG}"
  nmcli device connect ${NIC1NAME} &>>"${LOG}"
  # And give it time to find an address.
  sleep 3
}

#########################################################################################################

dhcp_config(){
echo "   Configuring DHCP Service" | tee -a "${LOG}"
sed -i.bak -e s/DHCPDARGS=/DHCPDARGS=${NIC2NAME}/ /etc/sysconfig/dhcpd
cat >/etc/dhcp/dhcpd.conf <<EOF
authoritative;
default-lease-time 14400;
max-lease-time 14400;
lease-file-name "/var/lib/dhcpd/dhcpd.leases";
ddns-update-style none;
option domain-name "example.com";
option subnet-mask 255.255.255.0;
option domain-name-servers 172.26.0.1;
option routers 172.26.0.1;

allow booting;
allow bootp;
option magic      code 208 = string;
option configfile code 209 = text;
option pathprefix code 210 = text;
option reboottime code 211 = unsigned integer 32;
class "pxeclients" {
   match if substring(option vendor-class-identifier, 0, 9) = "PXEClient";
   next-server 172.26.0.1;
   filename "pxelinux.0";
   # Reboot timeout after TFTP failure in seconds, 0 ~= forever
   option reboottime 30;
   # Magic was required for PXELINUX prior to v3.55
   option magic f1:00:74:7e;
   if exists dhcp-parameter-request-list {
     option dhcp-parameter-request-list = concat(option dhcp-parameter-request-list, d0, d1, d2, d3);
   }
}

subnet 172.26.0.0 netmask 255.255.255.0 {
        range 172.26.0.101 172.26.0.151;
}

host station1 {
        option host-name "station1";
        fixed-address 172.26.0.201;
        hardware ethernet 00:50:56:bb:75:ab;
}
host station2 {
        option host-name "station2";
        fixed-address 172.26.0.202;
        hardware ethernet 00:50:56:bb:55:3d;
}
EOF
systemctl enable dhcpd.service &>>"${LOG}"
systemctl start dhcpd.service &>>"${LOG}"
}

####################################################################################################

dns_config(){
echo "   Configuring DNS Service" | tee -a "${LOG}"
cat >/etc/named.conf <<EOF
options {
        directory "/var/named";
        # Forwarders are now set by scrape_dhcp_settings.sh
        #forwarders { 8.8.8.8; 8.8.4.4; };
        include "/etc/named.forwarders";
        listen-on { 127.0.0.1; 172.26.0/24; };
};
zone "example.com" IN {
        type master;
        file "db.example.com";
        allow-update { none; };
};
zone "0.26.172.in-addr.arpa" IN {
        type master;
        file "db.0.26.172.in-addr.arpa";
        allow-update { none; };
};
zone "4.2.3.0.5.1.0.2.1.1.e.d.7.0.d.f.ip6.arpa" IN {
		type master;
		file "db.4.2.3.0.5.1.0.2.1.1.e.d.7.0.d.f.ip6.arpa";
		allow-update {none; };
};
EOF
cat >/var/named/db.0.26.172.in-addr.arpa <<EOF
\$TTL 86400
@       IN      SOA     server1.example.com.    root.server1.example.com.       (
                                                20080915        ; Serial
                                                28800                   ; Refresh
                                                14400                   ; Retry
                                                3600000                 ; Expire
                                                86400 )                 ; Minimum


                        IN NS   server1.example.com.

1                       IN PTR  server1.example.com.
\$GENERATE 1-9  20\$    IN PTR  station\$.example.com.
\$GENERATE 10-${NUMOFWS}  2\$   IN PTR  station\$.example.com.

\$GENERATE 1-9   10\$     IN PTR  dhcp\$.example.com.
\$GENERATE 10-${NUMOFWS} 1\$      IN PTR  dhcp\$.example.com.
EOF
cat >/var/named/db.4.2.3.0.5.1.0.2.1.1.e.d.7.0.d.f.ip6.arpa <<EOF
;
; fd07:de11:2015:324::/64
;
; Zone file built with the IPv6 Reverse DNS zone builder
; http://rdns6.com/
;
\$TTL 1h ; Default TTL
\$ORIGIN 4.2.3.0.5.1.0.2.1.1.e.d.7.0.d.f.ip6.arpa.
@   IN   SOA   server1.example.com.   root.server1.example.com.   (
    2015032401 ; serial
    1h         ; slave refresh interval
    15m        ; slave retry interval
    1w         ; slave copy expire time
    1h         ; NXDOMAIN cache time
    )

;
; domain name servers
;
@ IN NS server1.example.com.


; IPv6 PTR entries
1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.4.2.3.0.5.1.0.2.1.1.e.d.7.0.d.f.ip6.arpa.    IN    PTR    server1.example.com.

EOF
cat >/var/named/db.example.com <<EOF
\$TTL 86400
@       1D IN SOA       server1.example.com.       root.server1.example.com.    (
                                20080916                ; serial (yyyymmdd)
                                3H                      ; refresh
                                15M                     ; retry
                                1W                      ; expiry
                                1D )                    ; minimum

                IN      NS      server1.example.com.

; station1      IN A    172.26.0.101
server1         IN A    172.26.0.1
server1         IN AAAA FD07:DE11:2015:0324::1
\$GENERATE 1-9 station\$  IN A    172.26.0.20\$
\$GENERATE 10-${NUMOFWS} station\$  IN A    172.26.0.2\$

\$GENERATE 1-9 dhcp\$    IN A    172.26.0.10\$
\$GENERATE 10-${NUMOFWS} dhcp\$  IN A    172.26.0.1\$
EOF
for i in `seq 1 9`; do
cat >/var/named/db.station$i.com <<EOF
\$TTL 86400
@       1D IN SOA       server1.example.com.       root.server1.example.com.    (
                                20080921                ; serial (yyyymmdd)
                                3H                      ; refresh
                                15M                     ; retry
                                1W                      ; expiry
                                1D )                    ; minimum

                IN      NS      station$i.com.
                IN      NS      station$i.example.com.
                IN      NS      server1.example.com.

                IN MX 10    station$i.com
                IN A    172.26.0.20$i
www             IN A    172.26.0.20$i
ns              IN A    172.26.0.20$i
EOF
done

for i in `seq 10 ${NUMOFWS}`; do
cat >/var/named/db.station$i.com <<EOF
\$TTL 86400
@       1D IN SOA       server1.example.com.       root.server1.example.com.    (
                                20080921                ; serial (yyyymmdd)
                                3H                      ; refresh
                                15M                     ; retry
                                1W                      ; expiry
                                1D )                    ; minimum

                IN      NS      station$i.com.
                IN      NS      station$i.example.com.
                IN      NS      server1.example.com.

                IN A    172.26.0.2$i
                IN MX 10 172.26.0.2$i
www             IN A    172.26.0.2$i
ns              IN A    172.26.0.2$i
EOF
done


for i in `seq 1 9`; do
cat >>/etc/named.conf <<EOF
zone "station$i.com" IN {
        type master;
        file "db.station$i.com";
        allow-update { none; };
        allow-transfer { 172.26.0.20$i; };
};
EOF
done

for i in `seq 10 ${NUMOFWS}`; do
cat >>/etc/named.conf <<EOF
zone "station$i.com" IN {
        type master;
        file "db.station$i.com";
        allow-update { none; };
        allow-transfer { 172.26.0.2$i; };
};
EOF
done

if [ ! -f /etc/named.forwarders ]; then
  cat >>/etc/named.forwarders <<EOF
forwarders { 
  8.8.8.8;
  8.8.4.4;
};
EOF
fi

systemctl enable named.service &>>"${LOG}"
systemctl start named.service &>>"${LOG}"
}

###########################################################################################################

tftp_config(){
echo "   Configuring TFTP Service" | tee -a "${LOG}"
touch /etc/xinetd.d/tftp
cat >/etc/xinetd.d/tftp <<EOF
# default: off
# description: The tftp server serves files using the trivial file transfer \
#	protocol.  The tftp protocol is often used to boot diskless \
#	workstations, download configuration files to network-aware printers, \
#	and to start the installation process for some operating systems.
service tftp
{
	socket_type		= dgram
	protocol		= udp
	wait			= yes
	user			= root
	server			= /usr/sbin/in.tftpd
	server_args		= -v -s /var/lib/tftpboot
	disable			= no
	per_source		= 11
	cps			= 100 2
	flags			= IPv4
}
EOF
sed -r -i.bak -e 's/(disable\s*=\s*)(yes)/\1no/'  -e 's/(server_args\s*)(=\s*-s)/\1= -v -s/' /etc/xinetd.d/tftp
echo "Reloading xinetd.service"  &>>"${LOG}"
systemctl reload xinetd.service  &>>"${LOG}"
sleep 2
echo "Checking xinetd.service and starting if still needed"  &>>"${LOG}"
( systemctl is-active xinetd.service || systemctl start xinetd.service ) &>>"${LOG}"
}
###############################################################################################################
pxe_config() {

echo "   Configuring PXE Service" | tee -a "${LOG}"
mkdir -p /var/lib/tftpboot/pxelinux.cfg &>>"${LOG}"

PXEDEFAULT=`echo "${ISOMOUNTDIRREL}" | cut -d "/" -f 1`

cat >/var/lib/tftpboot/pxelinux.cfg/default <<EOF
default menu.c32
prompt 0
timeout 300
ONTIMEOUT local
menu title #### PXE Boot Menu ####
 
label Q
  menu label ^Q) Quit PXE
  localboot 0

EOF

PXEMENUNUM=0
for full_path in `find ${FTPDIR} -name pxeboot -type d` ; do
	# Note that this loop is checking for the name of the subdirectory under 'pub'.
	# It is expected that each RHEL version will be in a different subdir of 'pub' directly
	# rather than something like 'pub/RHEL/7.0', 'pub/RHEL/7.1', etc.
	#echo $full_path
	# comp_name = extract the 5th field, delimiter /
	export comp_name=`echo $full_path|cut -d'/' -f5`
	mkdir -p /var/lib/tftpboot/$comp_name
	cp $full_path/* /var/lib/tftpboot/$comp_name/ &>>"${LOG}"

	let PXEMENUNUM++
	cat >>/var/lib/tftpboot/pxelinux.cfg/default <<EOF
label ${PXEMENUNUM}
  menu label ^${PXEMENUNUM}) ${comp_name}_manual_install
  kernel $comp_name/vmlinuz
  append initrd=${comp_name}/initrd.img root=live:http://server1.example.com/pub/${comp_name}/dvd/images/install.img repo=http://server1.example.com/pub/${comp_name}/dvd/

EOF
	let PXEMENUNUM++
	cat >>/var/lib/tftpboot/pxelinux.cfg/default <<EOF
label ${PXEMENUNUM}
  menu label ^${PXEMENUNUM}) ${comp_name}_kickstart_install
  kernel $comp_name/vmlinuz
  append initrd=${comp_name}/initrd.img root=live:http://server1.example.com/pub/${comp_name}/dvd/images/install.img repo=http://server1.example.com/pub/${comp_name}/dvd/ noipv6 ks=http://server1.example.com/pub/station_ks.cfg inst.nosave=all

EOF
	let PXEMENUNUM++
	cat >>/var/lib/tftpboot/pxelinux.cfg/default <<EOF
label ${PXEMENUNUM}
  menu label ^${PXEMENUNUM}) ${comp_name}_kickstart_nogui_install
  kernel $comp_name/vmlinuz
  append initrd=${comp_name}/initrd.img root=live:http://server1.example.com/pub/${comp_name}/dvd/images/install.img repo=http://server1.example.com/pub/${comp_name}/dvd/ noipv6 ks=http://server1.example.com/pub/station-nogui_ks.cfg inst.nosave=all


EOF
done

cp -a /usr/share/syslinux/pxelinux.0 /usr/share/syslinux/menu.c32 /usr/share/syslinux/libutil.c32 /usr/share/syslinux/ldlinux.c32 /var/lib/tftpboot/ &>>"${LOG}"
restorecon -R /var/lib/tftpboot/ &>>"${LOG}"
}

###############################################################################################################

ntp_config(){
echo "   Configuring NTP Service" | tee -a "${LOG}"
cat >/etc/chrony.conf.base <<EOF

stratumweight 0
driftfile /var/lib/chrony/drift
rtcsync
makestep 10 3
allow 172.26.0.0/24
allow fd07:de11:2015:0324::/64
bindcmdaddress 127.0.0.1
bindcmdaddress ::1
local stratum 10
keyfile /etc/chrony.keys
commandkey 1
generatecommandkey
noclientlog
logchange 0.5
logdir /var/log/chrony

EOF
chattr +i /etc/chrony.conf.base
cp /etc/chrony.conf.base /etc/chrony.conf
if [ ${DETECTEDOS} -lt 10 ]; then
  NTPPOOL="rhel."
elif [ ${DETECTEDOS} -lt 20 ]; then
  NTPPOOL="centos."
else
  NTPPOOL=""
fi
cat >>/etc/chrony.conf <<EOF
server pool.ntp.org iburst

EOF
chattr +i /etc/chrony.conf

systemctl enable chronyd.service &>>"${LOG}"
systemctl start  chronyd.service &>>"${LOG}"
}

##############################################################################

ldap_config() {

echo "   Configuring LDAP Service" | tee -a "${LOG}"
echo "Starting the new LDAP stuff" &>>"${LOG}"

dnf module install -y idm:DL1/{server,client} &>>"${LOG}"
ipa-server-install -U -p P@ssw0rd! -a P@ssw0rd! -n EXAMPLE.COM -r EXAMPLE.COM &>>"${LOG}"
firewall-cmd --permanent --add-service={ldap,ldaps,kerberos,ntp,http,https} --zone=internal &>>"${LOG}"
firewall-cmd --reload &>>"${LOG}"
ipactl status &>>"${LOG}"
echo -e "P@ssw0rd!" | kinit admin &>>"${LOG}"
klist &>>"${LOG}"
ipa config-show &>>"${LOG}"
systemctl enable --now nfs-server rpcbind &>>"${LOG}"
firewall-cmd --permanent --add-service={nfs,mountd,rpc-bind} --zone=internal &>>"${LOG}"
firewall-cmd --reload &>>"${LOG}"
mkdir /home/guests &>>"${LOG}"
echo '/home/guests *(rw,sync,no_subtree_check,root_squash)' >> /etc/exports &>>"${LOG}"
exportfs -rav &>>"${LOG}"
ipa service-add nfs/server1.example.com &>>"${LOG}"
ipa config-mod --homedirectory=/home/guests --defaultshell=/bin/bash &>>"${LOG}"

echo -e "redhat/nredhat" | ipa user-add ipauser1 --first=ipa --last=user1 --password &>>"${LOG}"
mkdir -m0750 -p /home/guests/ipauser1 &>>"${LOG}"
chown 181000001:181000001 /home/guests/ipauser1 &>>"${LOG}"
echo -e "redhat/nredhat" | ipa user-add ipauser2 --first=ipa --last=user2 --password &>>"${LOG}"
mkdir -m0750 -p /home/guests/ipauser2 &>>"${LOG}"
chown 181000002:181000002 /home/guests/ipauser2 &>>"${LOG}"
echo -e "redhat/nredhat" | ipa user-add ipauser3 --first=ipa --last=user3 --password &>>"${LOG}"
mkdir -m0750 -p /home/guests/ipauser3 &>>"${LOG}"
chown 181000003:181000003 /home/guests/ipauser3 &>>"${LOG}"
echo -e "redhat/nredhat" | ipa user-add ipauser4 --first=ipa --last=user4 --password &>>"${LOG}"
mkdir -m0750 -p /home/guests/ipauser4 &>>"${LOG}"
chown 181000004:181000004 /home/guests/ipauser4 &>>"${LOG}"
echo -e "redhat/nredhat" | ipa user-add ipauser5 --first=ipa --last=user5 --password &>>"${LOG}"
mkdir -m0750 -p /home/guests/ipauser5 &>>"${LOG}"
chown 181000005:181000005 /home/guests/ipauser5 &>>"${LOG}"

ipa host-add --ip-address 172.26.0.201 station1.example.com &>>"${LOG}"
ipa dnsrecord-add example.com ipaclient -ttl=3600 --a-ip-address 172.25.0.201 &>>"${LOG}"
ipa host-add --ip-address 172.26.0.202 station2.example.com &>>"${LOG}"
ipa dnsrecord-add example.com ipaclient -ttl=3600 --a-ip-address 172.25.0.202 &>>"${LOG}"
ipa host-add --ip-address 172.26.0.203 station3.example.com &>>"${LOG}"
ipa dnsrecord-add example.com ipaclient -ttl=3600 --a-ip-address 172.25.0.203 &>>"${LOG}"
ipa host-add --ip-address 172.26.0.204 station4.example.com &>>"${LOG}"
ipa dnsrecord-add example.com ipaclient -ttl=3600 --a-ip-address 172.25.0.204 &>>"${LOG}"
ipa host-add --ip-address 172.26.0.205 station5.example.com &>>"${LOG}"
ipa dnsrecord-add example.com ipaclient -ttl=3600 --a-ip-address 172.25.0.205 &>>"${LOG}"
ipa host-add --ip-address 172.26.0.206 station6.example.com &>>"${LOG}"
ipa dnsrecord-add example.com ipaclient -ttl=3600 --a-ip-address 172.25.0.206 &>>"${LOG}"
ipa host-add --ip-address 172.26.0.207 station7.example.com &>>"${LOG}"
ipa dnsrecord-add example.com ipaclient -ttl=3600 --a-ip-address 172.25.0.207 &>>"${LOG}"
ipa host-add --ip-address 172.26.0.208 station8.example.com &>>"${LOG}"
ipa dnsrecord-add example.com ipaclient -ttl=3600 --a-ip-address 172.25.0.208 &>>"${LOG}"
ipa host-add --ip-address 172.26.0.209 station9.example.com &>>"${LOG}"
ipa dnsrecord-add example.com ipaclient -ttl=3600 --a-ip-address 172.25.0.209 &>>"${LOG}"

echo "Finished the new LDAP stuff" &>>"${LOG}"
}

##############################################################################

kerberos_config() {
echo "   Configuring Kerberos" | tee -a "${LOG}"

cat <<EOF | patch -b -d /var/kerberos/krb5kdc &>>"${LOG}"
--- kdc.conf_orig       2014-03-11 19:22:53.000000000 +0000
+++ kdc.conf    2015-07-01 02:03:50.212004811 +0000
@@ -5,5 +5,6 @@
 [realms]
  EXAMPLE.COM = {
-  #master_key_type = aes256-cts
+  master_key_type = aes256-cts
+  default_principal_flags = +preauth
   acl_file = /var/kerberos/krb5kdc/kadm5.acl
   dict_file = /usr/share/dict/words
EOF

[ ! -f /etc/krb5.conf_orig ] && cp -a /etc/krb5.conf /etc/krb5.conf_orig
cat <<EOF >/etc/krb5.conf 2>>"${LOG}"
[logging]
 default = FILE:/var/log/krb5libs.log
 kdc = FILE:/var/log/krb5kdc.log
 admin_server = FILE:/var/log/kadmind.log

[libdefaults]
 dns_lookup_realm = false
 ticket_lifetime = 24h
 renew_lifetime = 7d
 forwardable = true
 rdns = false
 default_realm = EXAMPLE.COM
 default_ccache_name = KEYRING:persistent:%{uid}

 default_realm = EXAMPLE.COM
 dns_lookup_kdc = false
[realms]
 EXAMPLE.COM = {
  kdc = server1.example.com
  admin_server = server1.example.com
 }

[domain_realm]
 .example.com = EXAMPLE.COM
 example.com = EXAMPLE.COM
EOF



echo "Kernel entropy pool value before: `cat /proc/sys/kernel/random/entropy_avail`" &>>"${LOG}"
echo -e "redhat\nredhat" | kdb5_util create -s -r EXAMPLE.COM &>>"${LOG}"
echo "Kernel entropy pool value after: `cat /proc/sys/kernel/random/entropy_avail`" &>>"${LOG}"

systemctl enable krb5kdc &>>"${LOG}"
systemctl enable kadmin &>>"${LOG}"
systemctl start krb5kdc &>>"${LOG}"
systemctl start kadmin &>>"${LOG}"


KADMINCMDS="${PITD}/kadmin.local_cmds"
cat <<EOF > "${KADMINCMDS}"
addprinc root/admin
redhat
redhat

addprinc -randkey host/server1.example.com
addprinc -randkey nfs/server1.example.com
EOF
for i in `seq 1 ${NUMOFWS}`; do
  cat <<EOF >> "${KADMINCMDS}"
addprinc -randkey host/station${i}.example.com
addprinc -randkey nfs/station${i}.example.com
EOF
done
cat <<EOF >> "${KADMINCMDS}"

ktadd host/server1.example.com
ktadd nfs/server1.example.com
EOF
for i in `seq 1 ${NUMOFWS}`; do
  cat <<EOF >> "${KADMINCMDS}"
ktadd host/station${i}.example.com
ktadd nfs/station${i}.example.com
EOF
done
cat <<EOF >> "${KADMINCMDS}"

ktadd -k /var/kerberos/krb5kdc/kadm5.keytab kadmin/admin kadmin/changepw
quit
EOF

kadmin.local <"${KADMINCMDS}" &>>"${LOG}"

cp /etc/krb5.keytab ${FTPDIR}/materials/krb5.keytab
chmod a+r ${FTPDIR}/materials/krb5.keytab &>>"${LOG}"

for NUM in `seq -w -s " " 1 ${NUMOFWS}`; do
  echo -e "redhat\nredhat" | kadmin.local -q "addprinc guest${NUM}" &>>"${LOG}"
done

cat <<EOF | patch -b -d /etc/ssh &>>"${LOG}"
--- ssh_config_orig     2014-03-19 20:50:07.000000000 +0000
+++ ssh_config  2015-07-01 03:16:39.423873305 +0000
@@ -51,4 +51,5 @@
 Host *
        GSSAPIAuthentication yes
+       GSSAPIDelegateCredentials yes
 # If this option is set to yes then remote X11 clients will have full access
 # to the original X11 display. As virtually no X11 client supports the untrusted
EOF

cat <<EOF >/etc/firewalld/services/kerberos.xml 2>>"${LOG}"
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>Kerberos</short>
  <description>Kerberos network authentication protocol server</description>
  <port protocol="tcp" port="88"/>
  <port protocol="udp" port="88"/>
  <port protocol="tcp" port="749"/>
</service>
EOF

authconfig --enablekrb5 --update &>>"${LOG}"

cat <<EOF | patch -b -d /etc &>>"${LOG}"
--- idmapd.conf_orig	2014-01-26 12:33:44.000000000 +0000
+++ idmapd.conf	2015-08-13 20:33:47.151534977 +0000
@@ -3,5 +3,5 @@
 # The following should be set to the local NFSv4 domain name
 # The default is the host's DNS domain name.
-#Domain = local.domain.edu
+Domain = example.com
 
 # The following is a comma-separated list of Kerberos realm
@@ -18,6 +18,6 @@
 [Mapping]
 
-#Nobody-User = nobody
-#Nobody-Group = nobody
+Nobody-User = nfsnobody
+Nobody-Group = nfsnobody
 
 [Translation]
@@ -29,5 +29,5 @@
 # New methods may be defined and inserted in the list.
 # The default is "nsswitch".
-#Method = nsswitch
+Method = nsswitch
 
 # Optional.  This is a comma-separated, ordered list of
EOF


cp /etc/krb5.conf   ${FTPDIR}/materials/ &>>"${LOG}"
cp /etc/idmapd.conf ${FTPDIR}/materials/ &>>"${LOG}"

}

################################################################################################################

nfs_config() {
 echo "   Configuring NFS Service" | tee -a "${LOG}"
mkdir /home/server1 &>>"${LOG}"
mkdir -p /exports/nfssecure &>>"${LOG}"
mkdir -p /exports/nfs{1..3} &>>"${LOG}"
chown -R root:users /exports/ &>>"${LOG}"
chmod -R 1777 /exports/ &>>"${LOG}"

cat >/etc/exports <<EOF
${FTPDIR}        *(ro,sync)
/home/server1       *(rw,sync)
#/exports/nfssecure          *.example.com(sec=krb5,rw,fsid=0)
/exports/nfs1             *(rw,sync)
/exports/nfs2			  *(rw,sync)
/exports/nfs3             *(rw,sync)
EOF

cat >>/etc/sysconfig/nfs <<EOF

RQUOTAD_PORT=875
LOCKD_TCPPORT=32803
LOCKD_UDPPORT=32769
STATDARG=" -p 662 "
RPCMOUNTDOPTS=" -p 20048 " 
SECURE_NFS=yes
EOF

cat >> /etc/sysctl.d/20-nfs_nlm.conf <<EOF
fs.nfs.nlm_tcpport=32803
fs.nfs.nlm_udpport=32769
EOF

#systemctl enable nfs.target &>>"${LOG}"
systemctl enable nfs-server.service &>>"${LOG}"
#systemctl enable nfs-secure-server.service &>>"${LOG}"
#systemctl start nfs.target &>>"${LOG}"
systemctl start nfs-server.service &>>"${LOG}"
#systemctl start nfs-secure-server.service &>>"${LOG}"
}

###########################################################################################################3

samba_config(){
echo "   Configuring Samba Service" | tee -a "${LOG}"

mkdir -p /samba/{public,restricted,misc} &>>"${LOG}"
chmod -R 0777 /samba &>>"${LOG}"
semanage fcontext -a -t samba_share_t '/samba(/.*)?' &>>"${LOG}"
restorecon -Rv /samba &>>"${LOG}"
setsebool -P samba_enable_home_dirs on &>>"${LOG}"
[ ! -f /etc/samba/smb.conf.orig ] && cp -a /etc/samba/smb.conf /etc/samba/smb.conf.orig &>>"${LOG}"

cat <<EOF 1>>/etc/samba/smb.conf 2>>"${LOG}"
[global]
        workgroup = WORKGROUP
        server string = Samba Server Version %v
        log file = /var/log/samba/log.%m
        max log size = 100
        security = user
        passdb backend = tdbsam
[homes]
        comment = Home Directories
        browseable = no
        writeable = yes
[public]
        comment = Public Files
        path = /samba/public
        public = yes
[restricted]
        comment = restricted share
        path = /samba/restricted
        browseable = no
        writeable = yes
        write list = @smbuser
[misc]
		comment = Misc Share
		path - /samba/misc
		public = yes
EOF

systemctl enable smb.service nmb.service &>>"${LOG}"
systemctl start smb.service nmb.service &>>"${LOG}"
}

##########################################################################################################3

iscsi_config(){
echo "   Configuring iSCSI Service" | tee -a "${LOG}"

mkdir -p /var/lib/target &>>"${LOG}"

systemctl disable target.service &>>"${LOG}"
systemctl stop target.service &>>"${LOG}"
rm /etc/target/iscsi_batch_setup.tmp &>/dev/null

echo "clearconfig confirm=True" > /etc/target/iscsi_batch_setup.tmp
echo "saveconfig" >> /etc/target/iscsi_batch_setup.tmp
echo "exit" >> /etc/target/iscsi_batch_setup.tmp
echo "Running initial 'priming' commands for iSCSI targetcli." &>>"${LOG}"
script -c "targetcli < /etc/target/iscsi_batch_setup.tmp" -a "${LOG}" >/dev/null
echo "Clearing iSCSI configuration for real this time." &>>"${LOG}"
script -c "targetcli < /etc/target/iscsi_batch_setup.tmp" -a "${LOG}" >/dev/null

rm /etc/target/iscsi_batch_setup.tmp &>/dev/null
echo "set global auto_add_mapped_luns=false" >> /etc/target/iscsi_batch_setup.tmp
for i in `seq -w 1 ${NUMOFWS}`; do
  # The "backstores" line takes care of creating the files.  Nice!
  #dd if=/dev/zero of=/var/lib/target/station$i bs=1k count=25k &>>"${LOG}"
  cat >>/etc/target/iscsi_batch_setup.tmp <<EOF
  backstores/fileio create station${i} /var/lib/target/station${i} 25M
  iscsi/ create iqn.2014-12.example.com:station${i}-target
  iscsi/iqn.2014-12.example.com:station${i}-target/tpg1/portals/ create
  iscsi/iqn.2014-12.example.com:station${i}-target/tpg1/luns/ create /backstores/fileio/station${i}
  iscsi/iqn.2014-12.example.com:station${i}-target/tpg1/acls/ create iqn.2014-12.example.com:station${i} add_mapped_luns=true
EOF
done

echo "saveconfig" >> /etc/target/iscsi_batch_setup.tmp
echo "exit" >> /etc/target/iscsi_batch_setup.tmp

echo "Setting desired iSCSI configuration." &>>"${LOG}"
script -c "targetcli < /etc/target/iscsi_batch_setup.tmp" -a "${LOG}" >/dev/null

restorecon -R /var/lib/target

systemctl enable target.service &>>"${LOG}"
systemctl start target.service &>>"${LOG}"
}

##########################################################################################################

user_config(){
echo "   Configuring Lab Users" | tee -a "${LOG}"
groupadd smbuser &>>"${LOG}"

mkdir /home/server1 &>>"${LOG}"
for i in `seq -w 1 ${NUMOFWS}`; do
  # password flag
  # This block is not creating a group per user.  For now we don't care.
  useradd -g users -u 20$i -d /home/server1/guest$i guest$i  &>>"${LOG}"
  echo "P@ssw0rd" | passwd --stdin guest$i  &>>"${LOG}"
done

echo "   Configuring Certificates" | tee -a "${LOG}"
mkdir -p /etc/pki/CA/private
(umask 077;openssl genrsa -passout pass:cacertpass -out /etc/pki/CA/private/cakey.pem -des3 2048)  &>>"${LOG}"
openssl req -new -x509 -passin pass:cacertpass -key /etc/pki/CA/private/cakey.pem -days 3650 >/etc/pki/CA/cacert.pem <<EOF  2>>"${LOG}"
US
Texas
Round Rock
Dell

server1.example.com
root@server1.example.com
EOF

mkdir -p ${FTPDIR}/materials
rm -f ${FTPDIR}/materials/cacert.pem
cp /etc/pki/CA/cacert.pem ${FTPDIR}/materials/cacert.pem

touch /etc/pki/CA/index.txt
echo "01" > /etc/pki/CA/serial
touch /etc/pki/CA/cacert.srl
echo "01" > /etc/pki/CA/cacert.srl

cp /etc/pki/CA/cacert.pem /etc/openldap/certs/
ln -s /etc/openldap/certs/cacert.pem /etc/openldap/certs/`openssl x509 -hash -noout -in /etc/openldap/certs/cacert.pem`.0 &>>"${LOG}"

mkdir -p ${FTPDIR}/materials/certs &>>"${LOG}"

for i in `seq 1 ${NUMOFWS}`; do
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout "${FTPDIR}/materials/certs/geek${i}.key"  -out "${FTPDIR}/materials/certs/geek${i}.crt" <<EOF &>>"${LOG}"
US
Texas
Round Rock
Dell

geek${i}.example.com
root@station${i}.example.com
EOF
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout "${FTPDIR}/materials/certs/nerd${i}.key"  -out "${FTPDIR}/materials/certs/nerd${i}.crt" <<EOF &>>"${LOG}"
US
Texas
Round Rock
Dell

nerd${i}.example.com
root@station${i}.example.com
EOF
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout "${FTPDIR}/materials/certs/dweeb${i}.key" -out "${FTPDIR}/materials/certs/dweeb${i}.crt" <<EOF &>>"${LOG}"
US
Texas
Round Rock
Dell

dweeb${i}.example.com
root@station${i}.example.com
EOF
done


openssl req -new -x509 -nodes -out /etc/openldap/certs/cert.pem -keyout /etc/openldap/certs/priv.pem -days 365 <<EOF &>>"${LOG}"
US
Texas
Round Rock
Dell
Linux In A Box lab
server1.example.com
root@server1.example.com
EOF


echo "   Configuring Student Users" | tee -a "${LOG}"
for N in 1 2 3 4 5; do
  useradd -m -G smbuser user${N} &>>"${LOG}"
  echo "P@ssw0rd" | passwd --stdin user${N} &>>"${LOG}"
  echo -e "P@ssw0rd\nP@ssw0rd" | smbpasswd -a user${N} &>>"${LOG}"
done
  useradd student &>>"${LOG}"
  echo "P@ssw0rd" | passwd --stdin student &>>"${LOG}"
  echo -e "P@ssw0rd\nP@ssw0rd" | smbpasswd -a student &>>"${LOG}"
  for i in {student,user1,user2,user3,user4,user5}; do mkdir /home/$i/files; done
  for i in {student,user1,user2,user3,user4,user5}; do touch /home/$i/files/file{1..10}.txt; done
  echo "big brother is watching" | tee /home/*/files/file{1..10}.txt &>>"${LOG}"
  chmod -R 0660 /home/*/files
  for i in {student,user1,user2,user3,user4,user5}; do chown -R $i: /home/$i/files;done
}

################################################################################################################

misc2_config(){
echo "   Configuring Miscellaneous" | tee -a "${LOG}"

mandb &>>"${LOG}"

# Setting up a custom container module stream for podman 2.0
mkdir -p ${FTPDIR}/updates &>>"${LOG}"
(
	cd ${FTPDIR}/updates
	wget -i ${FTPDIR}/updates.list &>>"${LOG}"
	createrepo_c . &>>"${LOG}"
	modifyrepo_c --mdtype=modules ${FTPDIR}/modules.yml repodata/ &>>"${LOG}"
)

mkdir -p ${FTPDIR}/plusrepo &>>"${LOG}"
mkdir -p ${FTPDIR}/materials &>>"${LOG}"

(
	cd ${FTPDIR}/materials
	ln -s `find / -iname "lftp*x86_64.rpm" | head -n 1` lftp.rpm &>>"${LOG}"
	ln -s `find / -iname "zsh*x86_64.rpm" | head -n 1` zsh.rpm &>>"${LOG}"
)

ELT=`mktemp -d`
cp `find ${ISOMOUNTDIR} -iname "zsh*x86_64.rpm" | head -n 1` "${ELT}/zsh.rpm" &>>"${LOG}"
pushd "${ELT}" &>>"${LOG}"
tar -czf file.tar.gz zsh.rpm &>>"${LOG}"
popd &>>"${LOG}"
mv "${ELT}/file.tar.gz" "${FTPDIR}/" &>>"${LOG}"
rm "${ELT}" -rf  &>>"${LOG}"

(
cat >${FTPDIR}/materials/server1.repo <<EOF
[server1]
name=BaseOS
baseurl=http://server1.example.com/pub/centos-8.2/dvd/BaseOS
enabled=1
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial

[AppStream]
name=AppStream
baseurl=http://server1.example.com/pub/centos-8.2/dvd/AppStream
enabled=1
gpgcheck=0
EOF
)

(
cat >${FTPDIR}/materials/updates.repo <<EOF
[AppStream-updates]
name=AppStream Updates
baseurl=http://server1.example.com/pub/updates
enabled=1
gpgcheck=0
EOF
)

mkdir -m 700 -p /root/.ssh
ssh-keygen -q -t rsa -N '' -f /root/.ssh/id_rsa &>>"${LOG}"
cp /root/.ssh/id_rsa.pub "${FTPDIR}/materials/" &>>"${LOG}"
echo "UseDNS no" >>/etc/ssh/sshd_config
sed -e 's/#GSSAPIAuthentication no/GSSAPIAuthentication no/' -e 's/GSSAPIAuthentication yes/#GSSAPIAuthentication yes/' -i /etc/ssh/sshd_config
sed -e 's/IPTABLES_MODULES="/&ip_conntrack_ftp /' -i.bak /etc/sysconfig/iptables-config

cat >"/var/www/html/motivational.html"<<EOF
<h1>You can Do It!</h1>
<img src="trejo.png" alt="Trejo Believes in You">
EOF

cat >"/var/www/html/index.html"<<EOF
<h1>Welcome to Server1</h1>
EOF

useradd -g users -g 100 localuser &>>"${LOG}"
echo "P@ssw0rd" | passwd --stdin localuser &>>"${LOG}"

rpm --import ${YUMGPGPATH} &>>"${LOG}"
cat >"${FTPDIR}/materials/user-script.sh"<<EOF
echo "Hello World"
EOF

cat >"${FTPDIR}/materials/breakme1.sh"<<EOF
clear
echo $1$yRy7E5q7$dv4CJaRDsyhsbJBPeH/L81 | passwd --stdin root
echo "******************************"
echo
echo "Root Password has been changed"
echo "******************************"
echo
echo "System will reboot in 5 seconds"
echo "*******************************"
sleep 5
reboot
EOF
chmod 777 "${FTPDIR}/materials/breakme1.sh"
}

##########################################################################################################################

firewall_config(){
echo "   Configuring Firewall" | tee -a "${LOG}"
echo "Firewall rules start" &>>"${LOG}"
firewall-cmd --permanent --zone=external --change-interface=${NIC1NAME} &>>"${LOG}"
firewall-cmd --permanent --zone=internal --change-interface=${NIC2NAME} &>>"${LOG}"
firewall-cmd --permanent --zone=external --add-service=ssh &>>"${LOG}"
firewall-cmd --permanent --zone=external --add-service=ftp &>>"${LOG}"
firewall-cmd --permanent --zone=external --add-service=http &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-service=ssh &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-service=dhcp &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-service=dhcpv6 &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-service=dns &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-service=ftp &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-service=tftp &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-service=http &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-service=https &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-service=ldap &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-service=ldaps &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-service=kerberos &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-service=samba &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-service=ntp &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-port=3260/tcp &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-port=2049/tcp &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-port=2049/udp &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-port=111/tcp &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-port=111/udp &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-port=20048/tcp &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-port=20048/udp &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-port=875/tcp &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-port=875/udp &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-port=32803/tcp &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-port=32769/udp &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-port=662/tcp &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-port=662/udp &>>"${LOG}"
firewall-cmd --permanent --zone=internal --add-port=5000/tcp &>>"${LOG}"
systemctl restart firewalld.service &>>"${LOG}"
sleep 10
iptables -nvL &>>"${PITD}/iptables_nvL"
firewall-cmd --list-all-zones &>>"${PITD}/firewall-cmd_list-all-zones"
echo "Firewall rules done" &>>"${LOG}"
}

###################################################################################################
containers (){
#assistance with commands here from Josh Davis jdavis@eoctech.edu
echo "   Configuring Containers" | tee -a "${LOG}"
#here we make our container registry directory
mkdir -pv /var/lib/registry &>>"${LOG}"
#now we setup the container registry file
cat >"/etc/containers/registries.conf"<<EOF 
[registries.search]
registries = ['docker.io']

[registries.insecure]
registries = ['server1:5000']

[registries.block]
registries = []
EOF
#here we create our local registry and activate it
podman run -d --privileged --name registry -p 5000:5000 -v /var/lib/registry:/var/lib/registry:z --restart=always registry:2 &>>"${LOG}"
podman generate systemd registry > /etc/systemd/system/registry-container.service 
chmod 755 /etc/systemd/system/registry-container.service &>>"${LOG}"
systemctl daemon-reload &>>"${LOG}"
systemctl enable --now registry-container.service &>>"${LOG}"
#now we pull some public containers to use locally
podman pull docker.io/library/httpd &>>"${LOG}"
podman pull docker.io/library/mariadb &>>"${LOG}"
#here we tag the public containers and add them to the local registry to be used
podman tag docker.io/library/httpd server1:5000/httpd &>>"${LOG}"
podman tag docker.io/library/mariadb server1:5000/mariadb &>>"${LOG}"
podman push server1:5000/httpd &>>"${LOG}"
podman push server1:5000/mariadb &>>"${LOG}"
echo "container config complete" &>>"${LOG}"
}
###################################################################################################
###################################################################################################

materials_config(){
echo "   Tying up loose ends" | tee -a "${LOG}"
pushd ${FTPDIR}/materials &>/dev/null
unzip -o ../extras.zip &>>"${LOG}"
popd &>/dev/null

chown root:root ${FTPDIR}/ -R &>/dev/null

cp ${FTPDIR}/materials/sl.rpm /var/www/html/pub/materials/ &>>"${LOG}"
cp ${FTPDIR}/materials/trejo.png /var/www/html/ &>>"${LOG}"
cp ${FTPDIR}/materials/shakespeare.txt /samba/public &>>"${LOG}"
cp ${FTPDIR}/materials/madcow.wav ${FTPDIR}/materials/Paradise_Lost.txt /samba/restricted &>>"${LOG}"
cp ${FTPDIR}/materials/Steam_Its_Generation_and_Use.txt /home/server1 &>>"${LOG}"
cp ${FTPDIR}/materials/War_and_Peace.txt /exports/nfssecure &>>"${LOG}"
cp ${FTPDIR}/materials/Calculus_Made_Easy.pdf /exports/nfs1 &>>"${LOG}"
cp ${FTPDIR}/materials/Alices_Adventures_in_Wonderland.txt /exports/nfs3 &>>"${LOG}"
cp ${FTPDIR}/materials/Moby_Dick.txt /exports/nfs2 &>>"${LOG}"
cp ${FTPDIR}/materials/The_History_Of_The_Decline_And_Fall_Of_The_Roman_Empire.txt /samba/misc &>>"${LOG}"
tar -xzf ${FTPDIR}/materials/ring.tgz -C /exports/nfssecure &>>"${LOG}"

echo "   Removing unused Magic" | tee -a "${LOG}"
if [ ${DONORMALCONFIG} -eq 1 ]; then
  `echo "Y2hjb24gLXQgYWRtaW5faG9tZV90IC92YXIvZnRwL3B1Yi9tYXRlcmlhbHMvc2hha2VzcGVhcmUudHh0Cg==" | base64 -d`
  SCRATCH=`mktemp`
  cat <<EOF | base64 -d > ${SCRATCH}
IyEvYmluL2Jhc2gKCkZpbmRXcml0YWJsZVJhbmRvbURpcigpIHsKICAjIFRoZSB2YXJpYWJsZSAi
RldSRCIgd2lsbCBiZSBzZXQgdG8gYSByYW5kb21seSBzZWxlY3RlZCBkaXJlY3RvcnkgaW4gd2hp
Y2gKICAjIHdlIGNhbiBjcmVhdGUgZmlsZXMuICBXZSB0cnkgdG8gYXZvaWQgdG91Y2h5IHBsYWNl
cyBsaWtlIC9zeXMsIHByaW50ZXIKICAjIHNwb29scywgZXRjLiAgSWYgeW91IHByb3ZpZGUgYSBm
aWxlbmFtZSB3ZSB3aWxsIGVuc3VyZSBpdCBkb2VzIG5vdCBjcmVhdGUKICAjIGEgY29uZmxpY3Qg
YW5kIHJldHVybiAiRldSREYiIHdpdGggdGhlIGZ1bGwgcGF0aCtmaWxlbmFtZS4KICBfX0ZXUkRT
Q1JBVENIPWBta3RlbXBgCiAgX19GV1JERklMRU5BTUU9IiR7MTotX19GV1JERklMRU5BTUVURVNU
fSIKICB3aGlsZSBbIC1mICIke19fRldSRFNDUkFUQ0h9IiBdOyBkbwogICAgIyBUaGUgc3RydWN0
dXJlIGlzICAgIGZpbmQgIFtSb290UGF0aHNdICBbRGlyZWN0b3JpZXNPbmx5XSAgW1Vud2FudGVk
TGlzdF0gIFtQcnVuZV0gIFtMb2dpY2FsT3JdIFtEaXJlY3Rvcmllc09ubHldIFtOb3RdW1Vud2Fu
dGVkTGlzdF0gIFtQcmludF0KICAgICMgWWVzIGl0J3MgYSBiaXQgbG9uZyBidXQgaXQgZG9lcyBp
biBvbmUgZWZmaWNpZW50IGNvbW1hbmQgd2hhdCB3b3VsZCBoYXZlIG90aGVyd2lzZSBuZWVkZWQg
cmVnZXgsIHRlbXAgZmlsZXMsIG9yIG90aGVyIG5hc3R5IGFwcHJvYWNoZXMuCiAgICBGV1JEPWBm
aW5kIC9ib290IC9ldGMgL2hvbWUgL29wdCAvcm9vdCAvdXNyIC92YXIgLXR5cGUgZCBcKCAtaW5h
bWUgImRldiIgLW8gLWluYW1lICJ1ZGV2IiAtbyAtaW5hbWUgInNwb29sIiAtbyAtaW5hbWUgInRt
cCIgLW8gLWluYW1lICJsb2NrIiAtbyAtaW5hbWUgIiouZCIgXCkgLXBydW5lIC1vIC10eXBlIGQg
ISBcKCAtaW5hbWUgImRldiIgLW8gLWluYW1lICJ1ZGV2IiAtbyAtaW5hbWUgInNwb29sIiAtbyAt
aW5hbWUgInRtcCIgLW8gLWluYW1lICJsb2NrIiAtbyAtaW5hbWUgIiouZCIgXCkgLXByaW50IDI+
L2Rldi9udWxsIHwgc29ydCAtUiB8IGhlYWQgLW4gMWAKICAgIEZXUkRGPSIke0ZXUkR9LyR7X19G
V1JERklMRU5BTUV9IgogICAgIyBBbmQgb2YgY291cnNlLCBjYW4gd2UgYWN0dWFsbHkgd3JpdGUg
dG8gdGhpcywgYW5kIG91ciB0YXJnZXQgZG9lc24ndCBleGlzdD8KICAgIHRvdWNoICIke0ZXUkR9
Ly5fX0ZXUkRURVNUIiAyPi9kZXYvbnVsbCAmJiBybSAiJHtGV1JEfS8uX19GV1JEVEVTVCIgJiYg
WyAhIC1mICR7RldSREZ9IF0gJiYgcm0gIiR7X19GV1JEU0NSQVRDSH0iCiAgZG9uZQp9CgojIENy
ZWF0ZSBzb21lIHRoaW5ncyBmb3Igc3R1ZGVudHMgdG8gc2VhcmNoIGZvci4KRmluZFdyaXRhYmxl
UmFuZG9tRGlyICIubXVsZGVyIjsgZWNobyAiVGhlIHRydXRoIGlzIExPT0sgT1VUIEJFSElORCBZ
T1UhIiA+ICIke0ZXUkRGfSIKRmluZFdyaXRhYmxlUmFuZG9tRGlyICIuMzQzIjsgZWNobyAiR3Jl
ZXRpbmdzISAgSSBhbSB0aGUgTW9uaXRvciBvZiBJbnN0YWxsYXRpb24gMDQuICBJIGFtIDM0MyBH
dWlsdHkgU3BhcmsuICBTb21lb25lIGhhcyByZWxlYXNlZCB0aGUgRmxvb2QuICBNeSBmdW5jdGlv
biBpcyB0byBwcmV2ZW50IGl0IGZyb20gbGVhdmluZyB0aGlzIEluc3RhbGxhdGlvbiwgYnV0IEkg
cmVxdWlyZSB5b3VyIGFzc2lzdGFuY2UuICBDb21lLiAgVGhpcyB3YXkuLiIgPiAiJHtGV1JERn0i
CkZpbmRXcml0YWJsZVJhbmRvbURpciAiLmJvbmVzIjsgZWNobyAiRGFuZ2l0LCBKaW0sIEknbSBh
IHN5c2FkbWluIG5vdCBhIHNlYXJjaCBlbmdpbmUhIiA+ICIke0ZXUkRGfSIKRmluZFdyaXRhYmxl
UmFuZG9tRGlyICIua2hhbiI7IGVjaG8gIkFoLCBLaXJrLCBteSBvbGQgZnJpZW5kLiAgRG8geW91
IGtub3cgdGhlIEtsaW5nb24gcHJvdmVyYiB0aGF0IHRlbGxzIHVzIHJldmVuZ2UgaXMgYSBkaXNo
IGJlc3Qgc2VydmVkIGNvbGQ/ICBJdCBpcyB2ZXJ5IGNvbGQgaW4gc3BhY2UhIiA+ICIke0ZXUkRG
fSIKRmluZFdyaXRhYmxlUmFuZG9tRGlyICIucmFyZSI7IGVjaG8gIkNvbW1vbiBzZW5zZSBpcyBz
byByYXJlIGl0IHNob3VsZCBiZSBjb25zaWRlcmVkIGEgc3VwZXItcG93ZXIuIiA+ICIke0ZXUkRG
fSIKRmluZFdyaXRhYmxlUmFuZG9tRGlyICJqb2tlciI7IGVjaG8gIkhhdmUgeW91IGV2ZXIgZGFu
Y2VkIHdpdGggdGhlIGRldmlsIGluIHRoZSBwYWxlIG1vb25saWdodD8iID4gIiR7RldSREZ9IgpG
aW5kV3JpdGFibGVSYW5kb21EaXIgImJvcm9taXIiOyBlY2hvICJPbmUgZG9lcyBub3Qgc2ltcGx5
IHdhbGsgaW50byBNb3Jkb3IuIEkgdHMgQmxhY2sgR2F0ZXMgYXJlIGd1YXJkZWQgYnkgbW9yZSB0
aGFuIGp1c3QgT3Jjcy4gIFRoZXJlIGlzIGV2aWwgdGhlcmUgdGhhdCBkb2VzIG5vdCBzbGVlcCwg
YW5kIHRoZSBHcmVhdCBFeWUgaXMgZXZlciB3YXRjaGZ1bC4gIEl0IGlzIGEgYmFycmVuIHdhc3Rl
bGFuZCwgcmlkZGxlZCB3aXRoIGZpcmUgYW5kIGFzaCBhbmQgZHVzdCwgdGhlIHZlcnkgYWlyIHlv
dSBicmVhdGhlIGlzIGEgcG9pc29ub3VzIGZ1bWUuICBOb3Qgd2l0aCB0ZW4gdGhvdXNhbmQgbWVu
IGNvdWxkIHlvdSBkbyB0aGlzLiAgSXQgaXMgZm9sbHkuIiA+ICIke0ZXUkRGfSIKRmluZFdyaXRh
YmxlUmFuZG9tRGlyICJ2YWRlciI7IGVjaG8gIllvdSBtYXkgZGlzcGVuc2Ugd2l0aCB0aGUgcGxl
YXNhbnRyaWVzLCBDb21tYW5kZXIuICBJIGFtIGhlcmUgdG8gcHV0IHlvdSBiYWNrIG9uIHNjaGVk
dWxlLiIgPiAiJHtGV1JERn0iCkZpbmRXcml0YWJsZVJhbmRvbURpciAiUnZCIjsgZWNobyAiRnJl
ZWxhbmNlciBwb3dlcnMsIGFjdGl2YXRlISIgPiAiJHtGV1JERn0iCkZpbmRXcml0YWJsZVJhbmRv
bURpciAiU3RhcldhcnMiOyBlY2hvICJNYXkgdGhlIGZvcmNlIGJlIHdpdGggeW91ISIgPiAiJHtG
V1JERn0iCkZpbmRXcml0YWJsZVJhbmRvbURpciAiZ3Jvb3QiOyBlY2hvICJJIGFtIEdyb290LiIg
PiAiJHtGV1JERn0iCkZpbmRXcml0YWJsZVJhbmRvbURpciAiLkNhc2FibGFuY2EiOyBlY2hvICJI
ZXJlJ3MgbG9va2luZyBhdCB5b3Uga2lkISIgPiAiJHtGV1JERn0iCkZpbmRXcml0YWJsZVJhbmRv
bURpciAiLmthdG5pc3MiOyBlY2hvICJJIHZvbHVudGVlciBhcyB0cmlidXRlISIgPiAiJHtGV1JE
Rn0iCkZpbmRXcml0YWJsZVJhbmRvbURpciAiLmh1bmdlcmdhbWVzIjsgZWNobyAiTWF5IHRoZSBv
ZGRzIGJlIGV2ZXIgaW4geW91ciBmYXZvciEiID4gIiR7RldSREZ9IgpGaW5kV3JpdGFibGVSYW5k
b21EaXIgIi5jaGlycnV0IjsgZWNobyAiSSBhbSBvbmUgd2l0aCB0aGUgZm9yY2UsIHRoZSBmb3Jj
ZSBpcyB3aXRoIG1lLiIgPiAiJHtGV1JERn0iCkZpbmRXcml0YWJsZVJhbmRvbURpciAiVGVybWlu
YXRvciI7IGVjaG8gIkknbGwgYmUgYmFjayEiID4gIiR7RldSREZ9IgpGaW5kV3JpdGFibGVSYW5k
b21EaXIgIi5UMiI7IGVjaG8gIkhhc3RhIGxhIHZpc3RhIGJhYnkuIiA+ICIke0ZXUkRGfSIKRmlu
ZFdyaXRhYmxlUmFuZG9tRGlyICIuSmF3cyI7IGVjaG8gIllvdSdyZSBnb25uYSBuZWVkIGEgYmln
Z2VyIGJvYXQhIiA+ICIke0ZXUkRGfSIKRmluZFdyaXRhYmxlUmFuZG9tRGlyICJnYW5kYWxmIjsg
ZWNobyAiWW91ISAgU2hhbGwgbm90ISAgUGFzcyEiID4gIiR7RldSREZ9IgpGaW5kV3JpdGFibGVS
YW5kb21EaXIgIi41dGgtRWxlbWVudCI7IGVjaG8gIkxlZWxvbyBEYWxsYXMgTXVsdGlwYXNzIiA+
ICIke0ZXUkRGfSIKRmluZFdyaXRhYmxlUmFuZG9tRGlyICIuQmFubmVyIjsgZWNobyAiVGhhdCdz
IG15IHNlY3JldCBDYXB0YWluLCBJJ20gYWx3YXlzIGFuZ3J5LiIgPiAiJHtGV1JERn0iCkZpbmRX
cml0YWJsZVJhbmRvbURpciAiLm1hdHJpeCI7IGVjaG8gIlRoZXJlIGlzIG5vIHNwb29uLiIgPiAi
JHtGV1JERn0iCkZpbmRXcml0YWJsZVJhbmRvbURpciAiLjMwMCI7IGVjaG8gIlRoaXMuLi4uIGlz
Li4uLiBTUEFSVEEhIiA+ICIke0ZXUkRGfSIKRmluZFdyaXRhYmxlUmFuZG9tRGlyICJodWxrIjsg
ZWNobyAiSHVsayBTTUFTSCEiID4gIiR7RldSREZ9IgpGaW5kV3JpdGFibGVSYW5kb21EaXIgInNw
b2NrIjsgZWNobyAiVGhlIG5lZWRzIG9mIHRoZSBtYW55IG91dHdlaWdoIHRoZSBuZWVkcyBvZiB0
aGUgZmV3LCBvciB0aGUgb25lLiIgPiAiJHtGV1JERn0iCkZpbmRXcml0YWJsZVJhbmRvbURpciAi
LnRpdGFuaWMiOyBlY2hvICJJJ20ga2luZyBvZiB0aGUgd29ybGQhIiA+ICIke0ZXUkRGfSIKRmlu
ZFdyaXRhYmxlUmFuZG9tRGlyICJwb3R0ZXIiOyBlY2hvICJXZSd2ZSBhbGwgZ290IGJvdGggbGln
aHQgYW5kIGRhcmsgaW5zaWRlIHVzLiAgV2hhdCBtYXR0ZXJzIHRoYXQgdGhlIHBhcnQgd2UgY2hv
b3NlIHRvIGFjdCBvbi4gIFRoYXTigJlzIHdobyB3ZSByZWFsbHkgYXJlLiIgPiAiJHtGV1JERn0i
CkZpbmRXcml0YWJsZVJhbmRvbURpciAiLmxlZ28iOyBlY2hvICJZb3Uga25vdywgSSBkb24ndCB3
YW50IHRvIHNwb2lsIHRoZSBwYXJ0eSBidXQsIGRvZXMgYW55b25lIG5vdGljZSB0aGF0IHdlJ3Jl
IHN0dWNrIGluIHRoZSBtaWRkbGUgb2YgdGhlIG9jZWFuIG9uIHRoaXMgY291Y2g/IERvIHlvdSBr
bm93IHdoYXQga2luZCBvZiBzdW5idXJuIEknbSBnb2luZyB0byBnZXQ/IE5vbmUsICdjYXVzZSBJ
J20gY292ZXJlZCBpbiBsYXRleCwgYnV0IHlvdSBndXlzIGFyZSBnb2luZyB0byBnZXQgc2VyaW91
c2x5IGZyaWVkLiBJIG1lYW4gaXQncyBub3QgbGlrZSBhLi4uIGxpa2UgYSBiaWcgZ2lnYW50aWMg
c2hpcCBpcyBqdXN0IGdvaW5nIHRvIGNvbWUgb3V0IG9mIG5vd2hlcmUgYW5kIHNhdmUgVVMgYnkg
Z29zaC4iID4gIiR7RldSREZ9IgpGaW5kV3JpdGFibGVSYW5kb21EaXIgImdhcmFrIjsgY2F0ID4g
IiR7RldSREZ9IiA8PEVPRgpTaXNrbzogV2hvJ3Mgd2F0Y2hpbmcgVG9sYXI/wqAKR2FyYWs6IEkn
dmUgbG9ja2VkIGhpbSBpbiBoaXMgcXVhcnRlcnMuICBJJ3ZlIGFsc28gbGVmdCBoaW0gd2l0aCB0
aGUgZGlzdGluY3QgaW1wcmVzc2lvbiB0aGF0IGlmIGhlIGF0dGVtcHRzIHRvIGZvcmNlIHRoZSBk
b29yIG9wZW4sIGl0IG1heSBleHBsb2RlLsKgClNpc2tvOiBJIGhvcGUgdGhhdCdzIGp1c3QgYW4g
aW1wcmVzc2lvbi7CoApHYXJhazogSXQncyBiZXN0IG5vdCB0byBkd2VsbCBvbiBzdWNoIG1pbnV0
aWFlCkVPRgpGaW5kV3JpdGFibGVSYW5kb21EaXIgInJpbmciOyBjYXQgPiAiJHtGV1JERn0iIDw8
RU9GCkFzaCBuYXpnIGR1cmJhdHVsw7trCmFzaCBuYXpnIGdpbWJhdHVsCmFzaCBuYXpnIHRocmFr
YXR1bMO7awphZ2ggYnVyenVtLWlzaGkga3JpbXBhdHVsCkVPRgoKIyBBdCB0aGUgcmVxdWVzdCBv
ZiBBYXJvbl9Tb3V0aGVybGFuZApGaW5kV3JpdGFibGVSYW5kb21EaXIgIi5kb25nbGUiOyBlY2hv
ICJEYW5naXQsIFdlcyEiID4gIiR7RldSREZ9IgoKIyBSZW1vdmUgY2x1ZXMgYWJvdXQgd2hhdCB3
ZSByZWNlbnRseSBkaWQKRldSRD0iIgpGV1JERj0iIgojIERlbGV0ZSBvdXJzZWx2ZXMKcm0gJHtT
Q1JBVENIfQo=
EOF
  . ${SCRATCH}
fi

tar -xzf ${FTPDIR}/ascii_art.tgz --no-overwrite-dir --no-selinux -C /  &>>"${LOG}"
AACT=`mktemp`
crontab -l > ${AACT} 2>>"${LOG}"
if ! grep -q "rotate_issue.sh" ${AACT}; then
  echo "*/5 * * * * /usr/local/bin/rotate_issue.sh &>/dev/null" >> ${AACT}
  crontab ${AACT}  &>>"${LOG}"
fi
rm ${AACT} &>/dev/null

SDS=`mktemp`
crontab -l > "${SDS}" 2>>"${LOG}"
if ! grep -q "scrape_dhcp_settings.sh" "${SDS}"; then
  echo "@reboot    /usr/local/sbin/scrape_dhcp_settings.sh &>/dev/null" >> "${SDS}"
  echo "57 * * * * /usr/local/sbin/scrape_dhcp_settings.sh &>/dev/null" >> "${SDS}"
  crontab "${SDS}"  &>>"${LOG}"
fi
rm "${SDS}" &>/dev/null
/usr/local/sbin/scrape_dhcp_settings.sh &>>"${LOG}"
mandb &>>"${LOG}"
updatedb &>>"${LOG}"
restorecon -Rv /var/www/* &>>"${LOG}"
restorecon -Rv /var/ftp/* &>>"${LOG}"
`echo "bG9nZ2VyIElcJ20gbWFraW5nIGEgbm90ZSBoZXJlOiBIVUdFIFNVQ0NFU1MK" | base64 -d`
echo "Loose ends tied up, extra magic removed"
echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-" | tee -a "${LOG}"
echo "Creating troubleshooting log bundle.  Please IGNORE ANY ERRORS you see." | tee -a "${LOG}"
history &> "${PITD}/history.txt"
pushd /tmp &>/dev/null
ls -alF ${PITD} >> "${LOG}"
set >> "${LOG}"
sosreport --tmp-dir "${PITD}" --batch &>> "${LOG}"
rm /root/LIAB_PostInstall_troubleshooting.zip &>/dev/null
zip -9r /root/LIAB_PostInstall_troubleshooting.zip ${PITD}/* &>/dev/null
cp -f /root/LIAB_PostInstall_troubleshooting.zip ${FTPDIR}/
popd &>/dev/null

EXTIP4=`ip -4 address show ${NIC1NAME} | grep "inet " | cut -d " " -f 6 | cut -d "/" -f 1`
if [ ! -z ${EXTIP4} ]; then
  echo "Log bundle available at:"
  echo "   http://${EXTIP4}/pub/LIAB_PostInstall_troubleshooting.zip"
else
  # I considered falling back to IPv6 here, but if the student/user is enough
  # of a newbie to need this level of hand-holding there isn't much chance
  # they'll figure out how to reach a link-local IPv6 URL in their browser.
  # I have no way of knowing what their interface name would be anyway.
  echo "I don't have an external IPv4 address right now, but the log was"
  echo "generated anyway.  It's in both /root and ${FTPDIR}."
fi

echo ""
echo ""
echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
echo ""
echo ""
echo "All done."
echo ""
echo ""
echo "Now we are going to reboot the server!"
echo ""
`echo "bG9nZ2VyIEl0XCdzIGhhcmQgdG8gb3ZlcnN0YXRlIG15IHNhdGlzZmFjdGlvbi4K" | base64 -d`
sleep 10
}

network_config
package_installation
misc1_config
dhcp_config
dns_config
tftp_config
pxe_config
ntp_config
nfs_config
samba_config
iscsi_config
user_config
misc2_config
ldap_config
kerberos_config
firewall_config
containers  
materials_config
reboot
