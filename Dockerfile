FROM debian:jessie
RUN apt-get update && \
	DEBIAN_FRONTEND=noninteractive apt-get -y install postfix sasl2-bin opendkim libsasl2-modules supervisor rsyslog spamassassin && \
	apt-get clean

# This is the hostname we want to have
ENV mailserver mx.jozsef.name

# Copy base config files
ADD supervisord.conf /etc/supervisor/conf.d/supervisord.conf
ADD opendkim.conf /etc/opendkim.conf

# Domains file contains mail users and passwords
ADD setup.sh secret/* /root/
WORKDIR /root
RUN /root/setup.sh

EXPOSE 25 587
CMD /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
