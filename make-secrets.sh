#! /bin/bash

#Change as required
server=mx.jozsef.name
country=GB
state=England
locality=Greater\ London
organization=$server
organizationalunit=
email=root@$server

mkdir -p secret
cd secret

if [ -f server.key ]; then
	echo 'Server key already exitst - remove it first'
	exit
fi

openssl genrsa -des3 -out server.key -passout pass:alma1234 1024
openssl rsa -in server.key -passin pass:alma1234 -out server.key
openssl req -new -key server.key -out server.csr -passin pass:alma1234 -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$domain/emailAddress=$email"
openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt
rm -f server.csr
openssl rsa -pubout -in server.key -out server.pub
