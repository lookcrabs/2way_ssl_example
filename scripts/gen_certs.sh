#!/bin/bash
set -ex

TEMP_DIR=$(mktemp -d /tmp/certs.XXXXXXXXXX)
cd ${TEMP_DIR}

if [[ -e /opt/ca.conf ]]
then
    cp /opt/ca.conf ${TEMP_DIR}
else
    echo "ca.conf doesnt exist. exiting"
    exit 1
fi

# Some Default Values
CERT_ROOT_DOMAIN="${1:-"poisoned.site"}"
CERT_ORG="${2:-"Gengar"}"
CERT_UNIT="${3:-"poison"}"
SERVER_SUBDOMAIN="${4:-"server"}"
SERVER_ALT_DOMAIN="${5:-"website"}"
CLIENT_SUBDOMAIN="${6:-"client"}"
CA_PASS="${7:-"mypassword"}"
SERVER_PASS="${8:-"mypassword"}"
CLIENT_PASS="${9:-"mypassword"}"


## ROOT CA
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 365 -sha256 -key ca.key -out ca.crt -subj "/CN=${CERT_ROOT_DOMAIN} CA/O=${CERT_ORG}"
touch index.txt
echo '01' > serial
openssl ca -config ca.conf -gencrl -keyfile ca.key -cert ca.crt -out crl.pem
openssl pkcs12 -export -chain -CAfile ca.crt -in ca.crt -inkey ca.key -passout pass:${CA_PASS} > ca.p12
openssl pkcs12 -in ca.p12 -passin pass:${CA_PASS} -nodes -out ca.pem

## SERVER
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr -subj "/CN=${SERVER_SUBDOMAIN}.${CERT_ROOT_DOMAIN}/O=${CERT_ORG}" -addext "subjectAltName = DNS:${SERVER_ALT_DOMAIN},DNS:${SERVER_ALT_DOMAIN}.${CERT_ROOT_DOMAIN}"
openssl ca -batch -config ca.conf -notext -in server.csr -out server.crt
openssl pkcs12 -export -chain -CAfile ca.crt -in server.crt -inkey server.key -passout pass:${SERVER_PASS} > server.p12
openssl pkcs12 -in server.p12 -passin pass:${SERVER_PASS} -nodes -out server.pem

## CLIENT
openssl genrsa -passout pass:${CLIENT_PASS} -out client.key 2048
openssl req -new -key client.key -passin pass:${CLIENT_PASS} -out client.csr -subj "/CN=${CLIENT_SUBDOMAIN}.${CERT_ROOT_DOMAIN}/O=${CERT_ORG}"
openssl ca -batch -config ca.conf -notext -in client.csr -out client.crt
openssl pkcs12 -export -chain -CAfile ca.crt -in client.crt -inkey client.key -passin pass:${CLIENT_PASS} -passout pass:${CLIENT_PASS} > client.p12
openssl pkcs12 -in client.p12 -passin pass:${CLIENT_PASS} -nodes -out client.pem

if [[ -d /qc/certificates/webservices ]]
then
    rsync -PaW ${TEMP_DIR}/ /qc/certificates/webservices/
fi
