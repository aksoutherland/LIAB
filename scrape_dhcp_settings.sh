#!/bin/bash

# Daniel_Johnson1@dell.com

# Pick out DNS and NTP settings from our DHCP lease so we can
# use the most optimal values instead of trying to guess.

# Interface we care about, based on knowing our connection name from Phase1
INTERFACE=`nmcli -t -f DEVICE,CONNECTION device | grep ":External$" | cut -f 1 -d ":"`

# What's the most recent lease file?
CURLEASE=`ls -1tr /var/lib/NetworkManager/dhclient*-${INTERFACE}.lease | tail -n 1`

[ ! -f "${CURLEASE}" ] && echo "No DHCP lease file for interface ${INTERFACE}, aborting!" && logger "scrape_dhcp_settings: No DHCP lease file" && exit 1

DNS1=`grep "option domain-name-servers" "${CURLEASE}" | tail -n 1 | cut -d " " -f 5 | cut -d ";" -f 1 | cut -d "," -f 1`
DNS2=`grep "option domain-name-servers" "${CURLEASE}" | tail -n 1 | cut -d " " -f 5 | cut -d ";" -f 1 | cut -d "," -f 2`
DNS3=`grep "option domain-name-servers" "${CURLEASE}" | tail -n 1 | cut -d " " -f 5 | cut -d ";" -f 1 | cut -d "," -f 3`

# The sed bit removes quotation marks and commas from the string
DNSSEARCH=`grep "option domain-search" "${CURLEASE}" | tail -n 1 | cut -d " " -f 5- | cut -d ";" -f 1 | sed 's/"//g;s/,//g'`

NTP1=`grep "option ntp-servers" "${CURLEASE}" | tail -n 1 | cut -d " " -f 5 | cut -d ";" -f 1 | cut -d "," -f 1`
NTP2=`grep "option ntp-servers" "${CURLEASE}" | tail -n 1 | cut -d " " -f 5 | cut -d ";" -f 1 | cut -d "," -f 2`
NTP3=`grep "option ntp-servers" "${CURLEASE}" | tail -n 1 | cut -d " " -f 5 | cut -d ";" -f 1 | cut -d "," -f 3`

# If only one value was given, we end up with duplicates.
[ "${DNS3}" == "${DNS2}" ] && DNS3=""
[ "${DNS2}" == "${DNS1}" ] && DNS2=""
[ "${NTP3}" == "${NTP2}" ] && NTP3=""
[ "${NTP2}" == "${NTP1}" ] && NTP2=""


##############################################################################
##############################################################################

rm /etc/named.forwarders.new &>/dev/null
echo "# Referenced from /etc/named.conf .  These are the external DNS servers" >> /etc/named.forwarders.new
echo "# we query when we don't have the answer.  They are set by scrape_dhcp_settings.sh ." >> /etc/named.forwarders.new
echo "forwarders {" >> /etc/named.forwarders.new
VALIDDNS=0
[ ! -z "${DNS1}" ] && echo "  ${DNS1};" >> /etc/named.forwarders.new && let VALIDDNS++
[ ! -z "${DNS2}" ] && echo "  ${DNS2};" >> /etc/named.forwarders.new && let VALIDDNS++
[ ! -z "${DNS3}" ] && echo "  ${DNS3};" >> /etc/named.forwarders.new && let VALIDDNS++
echo "};" >> /etc/named.forwarders.new
echo "" >> /etc/named.forwarders.new
# If this is the same config we had, pretend we didn't get any values
diff /etc/named.forwarders.new /etc/named.forwarders &>/dev/null && VALIDDNS=0
# Only overwrite the last file if we have something useful
[ ${VALIDDNS} -gt 0 ] && chattr -i /etc/named.forwarders && mv /etc/named.forwarders.new /etc/named.forwarders && systemctl restart named.service
rm /etc/named.forwarders.new &>/dev/null

##############################################################################
##############################################################################

rm /etc/resolv.conf.new &>/dev/null
VALIDRESOLV=1
echo "# Set by a script and file marked immutable to prevent changes by anything else" >> /etc/resolv.conf.new
# Always put our local zone first, of course.  With a trailing space!
echo -n "search example.com. " >> /etc/resolv.conf.new
# By default only the first SIX search domains are used.  They must be space-separated.
if [ -z "${DNSSEARCH}" ]; then
  # DHCP didn't provide any DNS search information, using a default set.
  #echo "eerclab.dell.com. okc.amer.dell.com. amer.dell.com. us.dell.com." >> /etc/resolv.conf.new
  # On the other hand, no point in guessing right now.  Let's just terminate
  # that hanging 'echo -n'.
  echo " " >> /etc/resolv.conf.new
else
  # DHCP provided a list of DNS zones we should search when given an unqualified name
  echo "${DNSSEARCH}" >> /etc/resolv.conf.new
fi
if [ "$1" == "phase1_temp" ]; then
  echo "# TEMPORARILY using the DHCP-provided DNS servers directly." >> /etc/resolv.conf.new
  echo "# Once our own DNS daemon is running this will be changed." >> /etc/resolv.conf.new
  if [ "$VALIDDNS" -gt 0 ]; then
    [ ! -z "${DNS1}" ] && echo "nameserver ${DNS1}" >> /etc/resolv.conf.new
    [ ! -z "${DNS2}" ] && echo "nameserver ${DNS2}" >> /etc/resolv.conf.new
    [ ! -z "${DNS3}" ] && echo "nameserver ${DNS3}" >> /etc/resolv.conf.new
  else
    echo "# Or not...  We didn't GET any valid DNS servers from DHCP!" >> /etc/resolv.conf.new
    echo "nameserver 127.0.0.1" >> /etc/resolv.conf.new
  fi
else
  echo "# Since we host our own DNS zone, we cannot use external resolvers" >> /etc/resolv.conf.new
  echo "# here.  They are configured as Forwarders in /etc/named.forwarders ." >> /etc/resolv.conf.new
  echo "nameserver 127.0.0.1" >> /etc/resolv.conf.new
fi
# If this is the same config we had, pretend we didn't get any values
diff /etc/resolv.conf.new /etc/resolv.conf &>/dev/null && VALIDRESOLV=0
# Only overwrite the last file if we have something useful
[ ${VALIDRESOLV} -gt 0 ] && chattr -i /etc/resolv.conf && mv /etc/resolv.conf.new /etc/resolv.conf && chattr +i /etc/resolv.conf
rm /etc/resolv.conf.new &>/dev/null

##############################################################################
##############################################################################

rm /etc/chrony.conf.new &>/dev/null
cp /etc/chrony.conf.base /etc/chrony.conf.new &>/dev/null
VALIDNTP=0
[ ! -z "${NTP1}" ] && echo "server ${NTP1} iburst" >> /etc/chrony.conf.new && let VALIDNTP++
[ ! -z "${NTP2}" ] && echo "server ${NTP2} iburst" >> /etc/chrony.conf.new && let VALIDNTP++
[ ! -z "${NTP3}" ] && echo "server ${NTP3} iburst" >> /etc/chrony.conf.new && let VALIDNTP++
# If this is the same config we had, pretend we didn't get any values
diff /etc/chrony.conf.new /etc/chrony.conf &>/dev/null && VALIDNTP=0
# Only overwrite the last file if we have something useful
[ ${VALIDNTP} -gt 0 ] && chattr -i /etc/chrony.conf && mv /etc/chrony.conf.new /etc/chrony.conf && chattr +i /etc/chrony.conf && systemctl restart chronyd.service
rm /etc/chrony.conf.new &>/dev/null

logger "scrape_dhcp_settings: DNS values ${DNS1} ${DNS2} ${DNS3}; NTP values ${NTP1} ${NTP2} ${NTP3}; DNSSEARCH ${DNSSEARCH}"
