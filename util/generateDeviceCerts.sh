#!/usr/bin/env bash

usage() {
	echo "Usage: $0 [-k <string>]" 1>&2
	exit 1
}

while getopts ":k:" o; do
	case "${o}" in
	k)
		k=${OPTARG}
		;;
	*)
		usage
		;;
	esac
done

PRIVATE_KEY="req -newkey rsa:2048 -nodes -sha256 -keyout private.key"
if [ $k ]; then
	ls $k &> /dev/null
	if [ $? != 0 ]; then
		echo "File not found."
		exit 1
	fi
	PRIVATE_KEY="req -new -key $k -nodes"
fi

openssl \
	${PRIVATE_KEY} \
	-out request.csr \
	-subj '/CN=iot-device' \
	-addext 'subjectAltName = DNS.1:localhost,IP.1:127.0.0.1' \
	-addext 'extendedKeyUsage = clientAuth' \
	-addext 'basicConstraints = CA:FALSE' \
	-addext 'keyUsage = digitalSignature, keyEncipherment' &> /dev/null

if [ $? != 0 ]; then
	echo "Faild in cerificates generation."
	exit 1
fi

echo $(cat request.csr) | sed 's@ -@\\n-@g' | sed 's@- @-\\n@g'
