#!/bin/bash -xev

#### UserData Incident Bot Helper Script
### Script Params, exported in Cloudformation
# ${REGION} == AWS::Region
# ${ACCESS_KEY} == HostKeys
# ${SECRET_KEY} == {"Fn::GetAtt" : [ "HostKeys", "SecretAccessKey" ]}
# ${HOSTNAME} == Nodename or Server URL
###

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# Add chef repo
curl -s https://packagecloud.io/install/repositories/chef/stable/script.deb.sh | bash

# Install cfn bootstraping tools
easy_install https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz

# Install awscli
pip install awscli

# Set hostname
hostname ${HOSTNAME} || error_exit 'Failed to set hostname'
echo ${HOSTNAME} > /etc/hostname || error_exit 'Failed to set hostname'

# Run aws config
aws configure set default.region ${REGION}
aws configure set aws_access_key_id ${ACCESS_KEY}
aws configure set aws_secret_access_key ${SECRET_KEY}

# Add chef repo
curl -s https://packagecloud.io/install/repositories/chef/stable/script.deb.sh | bash
apt-get update

# setup cookbooks directory
sudo mkdir -p /var/chef/cookbooks
sudo chmod -R 777 /var/chef/cookbooks

CHEFDIR=/var/chef/cookbooks
COOKBOOK='incident-bot'

# Copy over the cookbooks
CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

rm -f ${CHEFDIR}/${COOKBOOK}

# Install Chef
apt-get install -y chefdk || error_exit 'Failed to install chef'

# Create first-boot.json
cat > "/var/chef/cookbooks/first-boot.json" << EOF
{
   "run_list" :[
    "recipe[${COOKBOOK}]"
   ]
}
EOF

cat > "${CHEFDIR}/Berksfile" <<EOF
source 'https://supermarket.chef.io'
cookbook "${COOKBOOK}", path: "${CDIR}/${COOKBOOK}"
EOF

cd $CHEFDIR

# Install dependencies
berks vendor

# create client.rb file so that Chef client can find its dependant cookbooks
cat > "/var/chef/cookbooks/client.rb" <<EOF
cookbook_path File.join(Dir.pwd, 'berks-cookbooks')
EOF

# Run Chef
sudo chef-client -z -c "/var/chef/cookbooks/client.rb" -j "/var/chef/cookbooks/first-boot.json"
