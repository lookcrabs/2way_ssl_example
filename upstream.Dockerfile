# vim:set ft=dockerfile:
FROM haproxy:lts
LABEL version="1.0"
LABEL name="ssl-server"
EXPOSE 80
EXPOSE 443
COPY confs/server.cfg /usr/local/etc/haproxy.cfg
COPY qc /qc
COPY confs/hello.html /etc/haproxy/hello.html
