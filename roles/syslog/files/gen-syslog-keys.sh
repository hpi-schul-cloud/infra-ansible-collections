#! /bin/bash
openssl genrsa 2048 > syslog-ca-key.pem
openssl req -new -x509 -nodes -days 3600 -key syslog-ca-key.pem -out syslog-ca-cert.pem
openssl req -newkey rsa:2048 -days 3600 -nodes -keyout syslog-server-key.pem -out syslog-server-req.pem
openssl rsa -in syslog-server-key.pem -out syslog-server-key.pem 
openssl x509 -req -in syslog-server-req.pem -days 3600 -CA syslog-ca-cert.pem  -CAkey syslog-ca-key.pem  -set_serial 01 -out syslog-server-cert.pem

