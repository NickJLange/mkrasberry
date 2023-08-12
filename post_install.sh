#!/bin/bash

BASE=/Volumes/bootfs

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


if [ ! -d $BASE ];
	then exit 1
fi

touch $BASE/ssh
cp -f ./$WIFI $BASE

echo $WIFISSID

cat $WIFI  | sed -r -e 's/ssid=".+"/ssid="'"$WIFISSID"'"/g' -e 's/psk=".+"/psk="'"$WIFIPSK"'"/g' > $BASE/$WIFI

cat $BASE/$WIFI

USERCONF="userconf"

echo "Adding default user..."

cp -f ./$USERCONF $BASE
