#!/bin/bash

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
done < domains
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
done < domains	
chown postfix.sasl /etc/sasldb2
# Setup sasl
cat >> /etc/postfix/sasl/smtpd.conf <<EOF
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN CRAM-MD5 DIGEST-MD5 NTLM
EOF

### Enable TLS if we have a certificate
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
done < domains
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

### Cleanup by removing the configuration file
rm -f domains
