# Docker based mail forwarder and SMTP server using Postfix with SASL, DKIM, SPF, SRS and SpamAssassin support

THis is a simple mail forwarding setup which enables the user to forward emails sent to custom email domains (e.g. youremail@yourdomain.com) to another email provider such as Gmail.

It also provides an SSL-secured SMTP server for sending emails from these domains.

## Configuration

1. In the Dockerfile change the environment mailserver to the hostname of your mailserver 
2. Setup a parameter file in `secrets/mailboxes`
3. Generate SSL keys in the `secret` directory. Filenames should be `server.key` for the private key and `server.cer` for the certificate. (These are not committed to GIT for obvious reasons but you can use the script `make-secrets.sh` to generate new ones)

Once these changes are made the image should be built and shipped then run in _docker_. When running you should bind the ports 25 and 587. Keep in mind port 25 is required for mail delivery to work to your server and you cannot change this port number.

```
# To build
docker build -t mail .
# To run
docker run -d --name my_mailserver -p 25:25 -p 587:587 mail 
```

## Mailboxes file syntax
The syntax for the mailboxes file in `secrets/mailboxes` should be:

```
# Any lines starting with hash are comments
forwarded_email@your_domain target_email@gmail.com some_secret_password
```

Email forwarding is automatically setup for these emails (and only these emails, no relaying) and SMTP users are created using the same email credentials and the password as their password.

To configure SMTP delivery for your mailbox you'll need to specify your servername as an SMTP server, enable SSL/TLS security on port 587 and provide the email as the user and the password as the password.

## Domain setup

There are some steps required on your domain's DNS for the mail server to be configured properly.

First the host running the Docker image should have a valid hostname bound to a fixed IP, and proper DNS lookups - for example `mx.yourdomain.com`. There should be an `A` record pointing to the IP of the server with ideally a reverse DNS `PTR` record also setup. 

You will then need to add an `MX` record for each and every forwarded domain. The value should be - obviously - the server hostname.

You should also create an SPF record to deny any other mail servers (spammers typically) send emails using your domain address. A good setting is generally to create an SPF protection to restrict to server with an MX record only. To setup this, create a `TXT` record with a value `v=spf1 mx ~all`

For DKIM validation you will need to add the public key value in another `TXT` record. The public key in put in `server.pub` if you use `make-secrets.sh` or you should obtain it from OpenSSL.

The DKIM record should be another `TXT` record with a value such as `v=DKIM1; k=rsa; p=the_brutally_long_RSA_public_key`
 
 
## Spam filtering

To be nice to the forwarding email provider all email is run through SpamAssassin. Level 7+ spam is automatically discarded while level 5+ spam has its subject rewritten so that the target server would put it in a 'Spam' folder.