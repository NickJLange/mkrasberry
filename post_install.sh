#!/bin/bash

BASE=/Volumes/bootfs

if [ ! -d $BASE ];
	then exit 1
fi


WIFI=wpa_supplicant.conf

echo "Adding default wifi..."

if [ -z "$WIFISSID" ];
	then
	echo "SSID and PSK not defined as environmental variables. Bailing."
	exit 1
fi

if [ -z "$WIFIPSK" ];
	then
	echo "SSID and PSK not defined as environmental variables. Bailing."
	exit 1
fi
cp -f ./$WIFI $BASE
echo "Connecting to $WIFISSID"

cat $WIFI  | sed -r -e 's/ssid=".+"/ssid="'"$WIFISSID"'"/g' -e 's/psk=".+"/psk="'"$WIFIPSK"'"/g' > $BASE/$WIFI

#cat $BASE/$WIFI




echo "Enabling SSH / default user"
touch $BASE/ssh
USERCONF="userconf.txt"

echo "Adding default user..."

cp -f ./$USERCONF $BASE
