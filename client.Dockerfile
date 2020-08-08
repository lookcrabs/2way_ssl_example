# vim:set ft=dockerfile:
FROM haproxy:lts
LABEL version="1.0"
LABEL name="ssl-client"
EXPOSE 8080
COPY confs/client.cfg /usr/local/etc/haproxy.cfg
COPY qc /qc
