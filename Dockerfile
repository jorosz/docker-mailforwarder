FROM debian:stable
RUN apt-get update && \
	DEBIAN_FRONTEND=noninteractive apt-get -y install --fix-missing --no-install-recommends postfix sasl2-bin opendkim libsasl2-modules supervisor rsyslog spamassassin postsrsd spamc spamass-milter dovecot-common dovecot-imapd python-pkg-resources && \
	apt-get clean

# This is the hostname we want to have
ENV mailserver server.jozsef.name

# Copy base config files
ADD supervisord.conf /etc/supervisor/conf.d/supervisord.conf
ADD opendkim.conf /etc/opendkim.conf

# Domains file contains mail users and passwords
ADD setup.sh secret/server.* secret/mailboxes /root/
WORKDIR /root
RUN /root/setup.sh

EXPOSE 25 587 993
CMD /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
