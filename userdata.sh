#!/bin/bash -xv

#### UserData Incident Bot Helper Script
### Script Params, exported in Cloudformation
# ${ACCESS_KEY} == HostKeys
# ${SECRET_KEY} == {"Fn::GetAtt" : [ "HostKeys", "SecretAccessKey" ]}
# ${HOSTNAME} == Nodename or Server URL
# ${BUCKET} = BotBucket
# ${ENVIRONMENT} = Environment
# ${SLACK_TOKEN} = ENVSlackToken
# ${PAGERDUTY_API_KEY} = ENVPagerDutyAPIKey
# ${PAGERDUTY_SERVICE_API_KEY} = ENVPagerDutyServiceKey
# ${PAGERDUTY_SUBDOMAIN} = ENVPagerDutySubDomain
# ${PAGERDUTY_USER_ID} = ENVPagerDutyUserID
# ${PAGERDUTY_ROOM} = ENVPagerDutyRoom
# ${PAGERDUTY_SERVICES} = ENVPagerDutyServices
# ${LE_EMAIL} = ContactEmail
###

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

S3DIR='/opt/bot-s3'
CHEFDIR='/var/chef/cookbooks'

# Install S3FS Dependencies
sudo apt-get install -y automake autotools-dev g++ git libcurl4-gnutls-dev libfuse-dev libssl-dev libxml2-dev make pkg-config

# Install S3FS

# If directory exists, remove it
if [ -d "/tmp/s3fs-fuse" ]; then
  rm -rf /tmp/s3fs-fuse
fi

# If s3fs command doesn't exist, install
if [ ! -f "/usr/local/bin/s3fs" ]; then
  cd /tmp
  git clone https://github.com/s3fs-fuse/s3fs-fuse.git || error_exit 'Failed to clone s3fs-fuse'
  cd s3fs-fuse
  ./autogen.sh || error_exit 'Failed to run autogen for s3fs-fuse'
  ./configure || error_exit 'Failed to run configure for s3fs-fuse'
  make || error_exit 'Failed to make s3fs-fuse'
  sudo make install || error_exit 'Failed run make-install s3fs-fuse'
fi

# Set S3FS Credentials
echo ${ACCESS_KEY}:${SECRET_KEY} > /etc/passwd-s3fs || error_exit 'Failed to set s3fs-fuse credentials'
chmod 600 /etc/passwd-s3fs

# Create S3FS Mount Directory
if [ ! -d "${S3DIR}" ]; then
  mkdir ${S3DIR}
fi

# Mount S3 Bucket to Directory
s3fs -o allow_other -o umask=000 -o passwd_file=/etc/passwd-s3fs ${BUCKET} ${S3DIR} || error_exit 'Failed to mount s3fs'

# Install cfn bootstraping tools
easy_install https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz || error_exit 'Failed to install CFN Bootstrap Tools'

# Set hostname
hostname ${HOSTNAME} || error_exit 'Failed to set hostname'
echo ${HOSTNAME} > /etc/hostname || error_exit 'Failed to set hostname'


# Add chef repo
curl -s https://packagecloud.io/install/repositories/chef/stable/script.deb.sh | bash || error_exit 'Failed to add chef repo'
apt-get update

# setup cookbooks directory
if [ ! -d ${CHEFDIR} ]; then
  mkdir -p ${CHEFDIR}
fi

sudo chmod -R 777 ${CHEFDIR}

rm -f ${CHEFDIR}/${COOKBOOK}

# Install Chef
apt-get install -y chefdk || error_exit 'Failed to install chef'


# Setup Citadel Items
mkdir -p ${S3DIR}/pagerduty ${S3DIR}/slack ${S3DIR}/aws ${S3DIR}/redis

## Pagerduty
echo "${PAGERDUTY_API_KEY}" >> ${S3DIR}/pagerduty/api_key
echo "${PAGERDUTY_SERVICE_API_KEY}" >> ${S3DIR}/pagerduty/service_key
echo "${PAGERDUTY_USER_ID}" >> ${S3DIR}/pagerduty/user_id
echo "${PAGERDUTY_API_KEY}" >> ${S3DIR}/pagerduty/

## Slack
echo "${SLACK_TOKEN}" >> ${S3DIR}/slack/api_key

if [ ${ENVIRONMENT} == 'production' ]; then
    LE_ENDPOINT='https://acme-v01.api.letsencrypt.org'
else
    LE_ENDPOINT='https://acme-staging.api.letsencrypt.org'
fi

# Create json for CFN Params to Attributes
cat > "${CHEFDIR}/cfn.json" << EOF
{
  "${COOKBOOK}": {
    "citadel": {
        "bucket": "${BUCKET}",
        "access_key_id": "${ACCESS_KEY}",
        "secret_access_key": "${SECRET_KEY}"
    },
    "aws": {
        "domain": "${DOMAIN}"
    },
    "redis": {
        "dir": "${S3DIR}/redis"
    },
    "name": "${BOT_NAME}",
    "adapter": "slack",
    "git_source": "https://github.com/github/hubot.git",
    "version": "2.18.0",
    "daemon": "${DAEMON}",
    "config": {
        "HUBOT_PAGERDUTY_SUBDOMAIN": "${PAGERDUTY_SUBDOMAIN}",
        "HUBOT_PAGERDUTY_ROOM": "${PAGERDUTY_ROOM}",
        "HUBOT_PAGERDUTY_ENDPOINT": "/pagerduty",
        "HUBOT_PAGERDUTY_SERVICES": "${PAGERDUTY_SERVICES}"
    },
    "letsencrypt": {
        "endpoint": "${LE_ENDPOINT}",
        "contact": "mailto:${LE_EMAIL}"
    }
  },
  "run_list": [
    "recipe[${COOKBOOK}]"
  ]
}
EOF

cat > "${CHEFDIR}/Berksfile" <<EOF
source 'https://supermarket.chef.io'
cookbook "${COOKBOOK}", git: 'https://github.com/HearstAT/cookbook-incident-bot.git'
EOF

# Install dependencies
sudo su -l -c "cd ${CHEFDIR} && export BERKSHELF_PATH=${CHEFDIR} && berks vendor" || error_exit 'Failed to run berks vendor'

# Create client.rb
cat > "/etc/chef/client.rb" <<EOF
cookbook_path "${CHEFDIR}/berks-cookbooks"
json_attribs "${CHEFDIR}/cfn.json"
EOF

# Run Chef
sudo su -l -c 'chef-client -z -c "/etc/chef/client.rb"' || error_exit 'Failed to run chef-client'
