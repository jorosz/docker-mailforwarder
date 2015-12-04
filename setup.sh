#!/bin/bash

if [ -z server.crt ] || [ -z server.key ] || [ -z mailboxes ]; then
	echo "** ERROR. You're missing secret files required for the build."
	echo "   Make sure you create server.key, server.crt and mailboxes in secrets/"
	exit 1
fi

# Remove comments and empty lines from mailboxes file
sed -i -e '/^\s*$/d' -e '/\s*#.*$/d' mailboxes

# Server certificate
mv server.crt server.key /etc/postfix/

postconf -e myhostname=$mailserver
postconf -e mydomain=$mailserver
postconf -F '*/*/chroot = n'

## Setup virtual aliases, generate /etc/postfix/virtual from /root/domains
postconf -e virtual_alias_maps=hash:/etc/postfix/virtual
while read email forward passwd; do
	echo "Add email map for $email -> $forward"
	echo "$email	$forward" >> /etc/postfix/virtual
	domains="$domains ${email#*@}"	
done < mailboxes
postmap /etc/postfix/virtual
postconf -e "virtual_alias_domains=$domains"
echo "Forwarding domains $domains" 


### Enable SASL
postconf -e smtpd_sasl_auth_enable=yes
postconf -e broken_sasl_auth_clients=yes
postconf -e smtpd_recipient_restrictions="permit_mynetworks permit_sasl_authenticated reject_unauth_destination reject_rbl_client zen.spamhaus.org reject_rbl_client bl.spamcop.net reject_rbl_client cbl.abuseat.org reject_unknown_client permit"
# generate SASL passwords for these entries
while read email forward passwd; do
	echo "Set SASL password for $email"
	echo $passwd | saslpasswd2 -p -c -u $mailserver $email 
done < mailboxes	
chown postfix.sasl /etc/sasldb2
# Setup sasl
cat >> /etc/postfix/sasl/smtpd.conf <<EOF
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN CRAM-MD5 DIGEST-MD5 NTLM
EOF

### Enable TLS 
postconf -e smtpd_tls_cert_file=/etc/postfix/server.crt
postconf -e smtpd_tls_key_file=/etc/postfix/server.key
chmod 400 /etc/postfix/server.key
postconf -M submission/inet="submission   inet   n   -   n   -   -   smtpd"
postconf -P "submission/inet/syslog_name=postfix/submission"
postconf -P "submission/inet/smtpd_tls_security_level=encrypt"
postconf -P "submission/inet/smtpd_sasl_auth_enable=yes"
postconf -P "submission/inet/milter_macro_daemon_name=ORIGINATING"
postconf -P "submission/inet/smtpd_recipient_restrictions=permit_sasl_authenticated,reject"	

## Enable OpenDKIM
mkdir -p /etc/opendkim
cp /etc/postfix/server.key /etc/opendkim/default.private

postconf -e milter_protocol=2
postconf -e milter_default_action=accept
postconf -e smtpd_milters=inet:localhost:12301
postconf -e non_smtpd_milters=inet:localhost:12301

cat >> /etc/opendkim/TrustedHosts <<EOF
127.0.0.1
localhost
$mailserver
EOF

while read email forward passwd; do
	echo  "default._domainkey.${email#*@} ${email#*@}:default:/etc/opendkim/default.private" >> /etc/opendkim/KeyTable
	echo  "$email default._domainkey.${email#*@}" >> /etc/opendkim/SigningTable
done < mailboxes
echo 'DKIM Sign Table'
cat /etc/opendkim/SigningTable
echo 'DKIM Key Table'
cat /etc/opendkim/KeyTable
chown opendkim /etc/opendkim/default.private

### Add some spam filtering
echo "/^X-Spam-Level: \*{7,}.*/ DISCARD spam">/etc/postfix/header_checks
postconf -e header_checks=regexp:/etc/postfix/header_checks
postconf -P "submission/inet/content_filter=spamassassin"
postconf -P "smtp/inet/content_filter=spamassassin"
postconf -M spamassassin/unix="spamassassin unix -     n       n       -       -       pipe user=debian-spamd argv=/usr/bin/spamc -f -e /usr/sbin/sendmail -oi -f \${sender} \${recipient}"
sed -i 's/^# rewrite_header Subject/rewrite_header Subject/' /etc/spamassassin/local.cf


### Configure SRSd
postconf -e sender_canonical_maps=tcp:127.0.0.1:10001
postconf -e sender_canonical_classes=envelope_sender
postconf -e recipient_canonical_maps=tcp:127.0.0.1:10002
postconf -e recipient_canonical_classes=envelope_recipient,header_recipient
domains2=$(echo $domains | tr ' ' ',')
cat >/etc/supervisor/conf.d/postsrsd.conf <<EOF
[program:postsrsd]
command=postsrsd -d$mailserver -s/etc/postsrsd.secret -unobody -c/var/lib/postsrsd -p/var/run/postsrs.pid -X$domains2
pidfile=/var/run/postsrsd.pid
EOF
cat /etc/supervisor/conf.d/postsrsd.conf

### Cleanup by removing the configuration file
rm -f mailboxes
