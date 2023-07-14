#!/bin/sh

#sleep 10h

/usr/bin/dounai start \
  --url $URL \
  --password $PASSWORD \
  --email $EMAIL \
  --email_host $EMAIL_HOST \
  --email_port $EMAIL_PORT \
  --email_auth_code $EMAIL_AUTH_CODE \
  --email_tls $EMAIL_TLS
