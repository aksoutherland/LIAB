#!/bin/bash
# Aaron.Southerland@dell.com   2016-11-28

clear
echo "This script checks the permissions on files and directories."

FILE1='/usr/local/bin/permissions.sh'
DIR1='/usr/local/src/testdir'
NEWPERM1='-rwxr-xr-x.'
NEWOWNER1='root'
NEWGROUP1='instructor'
NEWPERM2='drwxrwx---.'
NEWOWNER2='root'
NEWGROUP2='users'
LSFILE1=$(ls -l $FILE1)	#/usr/local/bin/permissions.sh
LSDIR1=$(ls -ld $DIR1)	#/usr/local/src/testdir
PERM1=$(echo "$LSFILE1" | cut -d ' ' -f 1)
OWNER1=$(echo "$LSFILE1" | cut -d ' ' -f 3)
GROUP1=$(echo "$LSFILE1" |cut -d ' ' -f 4)
PERM2=$(echo "$LSDIR1" | cut -d ' ' -f 1)
OWNER2=$(echo "$LSDIR1" | cut -d ' ' -f 3)
GROUP2=$(echo "$LSDIR1" | cut -d ' ' -f 4)

echo $LSFILE1
#echo "PERM1=$PERM1" ; echo "NEWPERM1=$NEWPERM1"
#echo "OWNER1=$OWNER1" ; echo "NEWOWNER1=$NEWOWNER1"
#echo "GROUP1=$GROUP1" ; echo "NEWGROUP1=$NEWGROUP1"
echo $LSDIR1
#echo "PERM2=$PERM2" ; echo "NEWPERM2=$NEWPERM2"
#echo "OWNER2=$OWNER2" ; echo "NEWOWNER2=$NEWOWNER2"
#echo "GROUP2=$GROUP2" ; echo "NEWGROUP2=$NEWGROUP2"

if [ "$PERM1" != "$NEWPERM1" ]; then
	echo "Permissions for $FILE1 are '$PERM1'. They should be '$NEWPERM1'."
else
	echo "Permissions for $FILE1 are '$NEWPERM1'.  SUCCESS!"
fi

if [ "$OWNER1" != "$NEWOWNER1" ] || [ "$GROUP1" != "$NEWGROUP1" ]; then
	echo "Owner and group for $FILE1 are $OWNER1:$GROUP1. They should be $NEWOWNER1:$NEWGROUP1."
else
	echo "Owner and group for $FILE1 are $NEWOWNER1:$NEWGROUP1.  SUCCESS!"
fi

if [ "$PERM2" != "$NEWPERM2" ]; then
	echo "Permissions for $DIR1 are '$PERM2'. They should be '$NEWPERM2'."
else
	echo "Permissions for $DIR1 are '$NEWPERM2'.  SUCCESS!"
fi

if [ "$OWNER2" != "$NEWOWNER2" ] || [ "$GROUP2" != "$NEWGROUP2" ]; then
	echo "Owner and group for $DIR1 are $OWNER2:$GROUP2. They should be $NEWOWNER2:$NEWGROUP2."
else
	echo "Owner and group for $DIR1 are $NEWOWNER2:$NEWGROUP2.  SUCCESS!"
fi
