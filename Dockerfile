FROM debian:jessie
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get -y install postfix sasl2-bin opendkim libsasl2-modules supervisor rsyslog

# This is the hostname we want to have
ENV mailserver mx.jozsef.name

# Copy base config files
ADD setup.sh /root/setup.sh
ADD supervisord.conf /etc/supervisor/conf.d/supervisord.conf
ADD opendkim.conf /etc/opendkim.conf

# Domains file contains mail users and passwords
ADD secret/domains /root/domains
# Server certificate
ADD secret/server.pem /etc/postfix/server.pem
# OpenDKIM certificate
ADD secret/default.private /etc/opendkim/default.private
# Setup script to run
RUN /root/setup.sh

EXPOSE 25 587
CMD /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
