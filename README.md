# Two-Way SSL with HAProxy
Quick example/guide on setting up:
 * Your own CA + server/client keys
 * 2 HAProxy instances using "Two-Way" SSL

You can quickly generate all of the certificates by running the below in the root of this repository
```
docker run -it                                              \
           -v ${PWD}/scripts/gen_certs.sh:/opt/gen_certs.sh \
           -v ${PWD}/confs/ca.conf:/opt/ca.conf             \
           -v ${PWD}/qc/:/qc/                               \
           haproxy:lts                                      \
           /bin/bash -c 'apt-get update && apt-get install -y openssl rsync && cd /opt/ && ./gen_certs.sh'
```

## Generate CA Key and Certificate
First step to creating a CA is to create its key:
```
openssl genrsa -out ca.key 4096
```
Next we create the certificate. We will create a self-singed certificate:
```
openssl req -new -x509 -days 365 -sha256 -key ca.key -out ca.crt -subj '/CN=poisoned.site CA/O=Gengar'
```
## Configure CA
Now that we have our key and certificate we can create a CA configuration file. Create a ca.conf file with the following content:
```
[ ca ]
default_ca   = BULLSHIZ_ca

[ crl_ext ]
authorityKeyIdentifier=keyid:always

[ BULLSHIZ_ca ]
DIR               = ./      # Default directory.
unique_subject    = no

certificate       = ${DIR}/ca.crt
database          = ${DIR}/index.txt

new_certs_dir     = ${DIR}/

private_key       = ${DIR}/ca.key
serial            = ${DIR}/serial

default_md        = sha256

name_opt          = ca_default
cert_opt          = ca_default
copy_extensions   = copyall

default_days      = 360
default_crl_days  = 360

policy            = BULLSHIZ_policy

[ BULLSHIZ_policy ]
C=      optional        # Country
ST=     optional        # State or province
L=      optional        # Locality
O=      supplied        # Organization
OU=     optional        # Organizational unit
CN=     supplied        # Common name
```

Note that we will use `copy_extensions = copyall.`
This carries security risks if you will sign certificates requests (CSR’s) that you did not generate yourself!
You should probably only use this if you also have full control over the CSR’s that will be signed. (like we do here)


Next create the certificate index file:
```
touch index.txt
```
And create the serial database:
```
echo '01' > serial
```
Finally, create the Certificate Revocation List (CRL):
```
openssl ca -config ca.conf -gencrl -keyfile ca.key -cert ca.crt -out crl.pem
```

This list is obviously "empty" for now as we haven't revoked any certificates yet.
Copy over the ca.crt and crl.pem files to a location where HAProxy can get it later, e.g.:
```
cp ca.crt /qc/certificates/webservices/
cp crl.pem /qc/certificates/webservices/
```

## Create HAProxy Key and Certificate
Create a private key:
```
openssl genrsa -out server.key 2048
```
Create a CSR:
```
openssl req -new -key server.key -out server.csr -subj '/CN=server.poisoned.site/O=Gengar' -addext 'subjectAltName = DNS:website,DNS:website.poisoned.site'
```
In the above CSR we define that HAProxy will run on a server `server.poisoned.site` (the CN), and that it will also have a DNS entry `website.poisoned.site.`
Let's now sign this certificate with our CA:
```
openssl ca -batch -config ca.conf -notext -in server.csr -out server.crt
```
For convenience package the key and certificate into a PKCS12 key store:
```
openssl pkcs12 -export -chain -CAfile ca.crt -in server.crt -inkey server.key -passout pass:mypassword > server.p12
```
Now that we have our HAProxy key and certificate, create a PEM file HAProxy can use:
```
openssl pkcs12 -in server.p12 -passin pass:mypassword -nodes -out server.pem
```
Now copy over the PEM file we created to a location where HAProxy can access it later, e.g.:
```
cp server.pem /qc/certificates/webservices/
```
Worth noting here is that we have signed the HAProxy certificate with our own CA, but this is actually not required for enabling two-way SSL authentication.
You can just as well use a certificate signed by a proper globally trusted CA instead.
In this case though, we just use our own CA.

## Run HAProxy
Create a file /etc/haproxy/haproxy.cfg with the following content:
```
global
    master-worker
    mworker-max-reloads 3
    daemon
    zero-warning
    # enable core dumps
    set-dumpable
    localpeer haproxy1

    ## log to stdout
    log stdout format raw local1 info
    log stderr format raw local1 warning

    stats socket /tmp/haproxy mode 666 level admin

    tune.bufsize 32000
    ssl-load-extra-files all
    ssl-default-bind-curves X25519:P-256

    # intermediate configuration ## Pulled from https://ssl-config.mozilla.org/ ## Aug 2nd 2020
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options no-sslv3 no-tlsv10 no-tlsv11 no-tls-tickets

    ssl-default-server-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-server-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-server-options no-sslv3 no-tlsv10 no-tlsv11 no-tls-tickets

    # curl https://ssl-config.mozilla.org/ffdhe2048.txt > /qc/certificates/dhparam
    ssl-dh-param-file /qc/certificates/dhparam

defaults
    mode http
    log global
    timeout client 5s
    timeout server 5s
    timeout connect 5s
    option redispatch
    option httplog

resolvers dns
    parse-resolv-conf
    resolve_retries       3
    timeout resolve       1s
    timeout retry         1s
    hold other           30s
    hold refused         30s
    hold nx              30s
    hold timeout         30s
    hold valid           10s
    hold obsolete        30s

frontend ft_test
    mode    http
    bind    :443 name https tfo ssl crt /qc/certificates/webservices/server.pem ca-file /qc/certificates/webservices/ca.crt crl-file /qc/certificates/webservices/crl.pem verify required alpn h2,http/1.1
    bind    :80  name http
    redirect scheme https code 301 if !{ ssl_fc }
    # HSTS (63072000 seconds)
    http-response set-header Strict-Transport-Security max-age=63072000
    use_backend static-subform

backend static-subform
  http-request return status 200 content-type "text/html; charset=utf-8" file /etc/haproxy/hello.html
```

Create a file `/etc/haproxy/hello.html` with the following contents:
```
<html xmlns="http://www.w3.org/1999/xhtml" >
  <head>
    <title>Hello World</title>
  </head>
  <body>
    <p> This is just a test</p>
  </body>
</html>
```

Run the HAProxy docker image with the above configuration and certificate files:
```
docker run -d -p 80:80 -p 443:443 \
    -v /etc/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg \
    -v /qc/certificates/:/qc/certificates/ \
    -v /etc/haproxy/hello.html:/etc/haproxy/hello.html
    haproxy:lts
```

## Create Client Certificate
Now that we have HAProxy up and running exposing our WebDAV and prometheus services, let’s create a client certificate so we can access it.

First create a client key:
```
openssl genrsa -passout pass:myclientpw -out client.key 2048
```
Next create the CSR:
```
openssl req -new -key client.key -passin pass:myclientpw -out client.csr -subj '/CN=client.poisoned.site/O=Gengar'
```
Sign this CSR so we generate a certificate:
```
openssl ca -batch -config ca.conf -notext -in client.csr -out client.crt
```
Create a PKCS12 key store so things are easier to distribute:
```
openssl pkcs12 -export -chain -CAfile ca.crt -in client.crt -inkey client.key -passin pass:myclientpw -passout pass:myclientpw > client.p12
```

## Curl using your client.ca
You can test your new client certificate with curl:
You'll need to use -k unless you add the ca.crt to your ca-authorities.
```
curl -E /qc/certificates/client.crt https://localhost:443 -k
```

## Setup upstream haproxy client
Follow the same steps for the server but use the following config:
```
global
    master-worker
    mworker-max-reloads 3
    daemon
    zero-warning
    # enable core dumps
    set-dumpable
    localpeer haproxy1

    ## log to stdout
    log stdout format raw local1 info
    log stderr format raw local1 warning

    stats socket /tmp/haproxy.sock mode 666 level admin

    tune.bufsize 32000
    ssl-load-extra-files all
    ssl-default-bind-curves X25519:P-256

    # intermediate configuration ## Pulled from https://ssl-config.mozilla.org/ ## Aug 2nd 2020
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options no-sslv3 no-tlsv10 no-tlsv11 no-tls-tickets

    ssl-default-server-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-server-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-server-options no-sslv3 no-tlsv10 no-tlsv11 no-tls-tickets

    # curl https://ssl-config.mozilla.org/ffdhe2048.txt > /qc/certificates/dhparam
    ssl-dh-param-file /qc/certificates/dhparam

defaults
    mode http
    log global
    timeout client 5s
    timeout server 5s
    timeout connect 5s
    option redispatch
    option httplog

resolvers dns
    parse-resolv-conf
    resolve_retries       3
    timeout resolve       1s
    timeout retry         1s
    hold other           30s
    hold refused         30s
    hold nx              30s
    hold timeout         30s
    hold valid           10s
    hold obsolete        30s

frontend ft_test
    mode    http
    bind    :80  name http
    # HSTS (63072000 seconds)
    http-response set-header Strict-Transport-Security max-age=63072000
    use_backend upstream-server

backend upstream-server
    mode    http
    server-template ssl-server 1 ssl-server:443 ssl crt /qc/certificates/webservices/client.pem ca-file /qc/certificates/webservices/ca.crt
```

Now run this docker container with the following:

```
docker run -d -p 8080:80 \
    -v /etc/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg \
    -v /qc/certificates/:/qc/certificates/ \
    haproxy:lts
```

With both containers running you should now be able to browse to localhost:8080 and see the contents of the hello.html

I've included a docker-compose file so you can just run `docker-compose up` to test this
