# cfn-incident-bot
Cloudformation Scripts to deploy incident bot into AWS

Utilizes companion cookbook [incident_bot](https://github.com/HearstAT/cookbook-incident-bot) to build out the HBM Incident Bot

# Prerequisites
These are things you will need to acquire in order to run the CFN Template in AWS

## Slack

### Token
You will need to generate a slack token for hubot.

1. Go to https://$yourteam.slack.com/services/new/hubot and create a new hubot integration
2. Choose a bot username, this is what you will call to the bot in rooms as (e.g.; @hubot help)
3. Find the API Token section (the token will start with `xoxb-`)

### Room Name
You will need room name/id for some of the bot features (e.g.; Checklist Announcement, Role Calls)
* Use the room name, #roomName (if public) or roomName (if private)
or
* Utilize https://api.slack.com/methods/channels.list tester function (or some other app) to pull down the channel list, search for channel name to find the id.

## Pagerduty
You will need to acquire the following items (per the [hubot-pager-me](https://github.com/hubot-scripts/hubot-pager-me) project)

* PAGERDUTY SUBDOMAIN - Your account subdomain (i.e.; $sudomain from $subdomain.pagerduty.com)
* PAGERDUTY USER ID - The user id of a PagerDuty user for your bot. You will have to create a API/Bot user within your pagerduty account for this ([pagerduty instructions](https://support.pagerduty.com/hc/en-us/articles/202828720-Adding-Users)).  NOTE this will be something like `ABC123S` not the email address or user name of the account.
* PAGERDUTY API KEY - Get one from https://$subdomain.pagerduty.com/api_keys; pagerduty instructions [here](https://support.pagerduty.com/hc/en-us/articles/202829310-Generating-an-API-Key). At the time of this writing [hubot-pager-me](https://github.com/hubot-scripts/hubot-pager-me) uses the V1 API so you will need to create a key of `v1 Legacy` and not `v2 Current`.
* PAGERDUTY SERVICE_API_KEY - Service API Key from a 'General API Service'. This should be assigned to a dummy escalation policy that doesn't actually notify, as hubot will trigger on this before reassigning it (pagerduty instructions [here](https://support.pagerduty.com/hc/en-us/articles/202830340-Creating-a-Generic-API-Service))
* PAGERDUTY SERVICES - (optional) Provide a comma separated list of service identifiers (e.g. PFGPBFY) to restrict queries to only those services. Get service id from the url after click on a service (e.g.; https://$subdomain.pagerduty.com/services/PFGPBFY)

## Contact Email
This will be required to get cert expiration notifications from the bot, we are utilizing letsencrypt.org to generate certs on the fly (they should renew automatically 30 days out via the cookbook) but just in-case you will get an email to verify

## AWS
These are the things you will need in AWS prior to running the CFN Template

* Hosted Zone ([AWS documentation](http://docs.aws.amazon.com/Route53/latest/DeveloperGuide/AboutHostedZones.html))
* VPC (There should be a default, unless you want a new one)
* SSH Security Group; just something that allows you port 22 via TCP from your IP. Must also be a part of the VPC chose previously
* Subnet, any will do as long as it belongs to the VPC and is routed to an Internet Gateway eventually
* Account with the following capabilities: [AWS::IAM::InstanceProfile, AWS::IAM::Policy, AWS::IAM::Role]

# Usage

* You will need to clone this repo or at least download the [incident-bot.json](incident-bot.json) to your machine (or alternatively upload to S3)
* Go to https://console.aws.amazon.com/cloudformation/
* Choose `Create Stack` or `Create New Stack`
* Choose `Upload a template to Amazon S3` (or alternatively `Specify an Amazon S3 template URL` if uploaded to S3)
* Fill out the Parameters with the items from the [Prerequisite](#prerequisites) section; click next
    * AWS Specific Settings (See [AWS](#aws) Section for info)
        * Pick a Server Size/Flavor:
        * Pick a default Key Pair for Access:
        * Pick VPC to Build Instance In:
        * Pick Security Group for SSH Access:
        * Pick Subnet to Build Instance In:
        * Enter Route53 Domain:
    * Slack Configuration (See [Slack](#slack) Section for info)
        * Enter Slack API Token:
        * Enter Slack Room:
    * Pager Duty Configuration (See [Pagerduty](#pagerduty) Section for info)
        * Enter Service API Key:
        * Enter Pager Duty Subdomain:
        * Enter Pager Duty User ID: (Ex. `ABC123S`)
        * Enter Slack Room for Pager Duty Alerts: (NOTE: for public channels the room name is fine. For private channels use the [Slack API Tester](https://api.slack.com/methods/groups.list/test) to find the channel ID that looks something like `ABC123S`)
        * Enter Pager Duty Services (Optional For Restriction):
    * Bot Configuration
        * Enter name for Bot: (Will not affect the name chosen in slack, but sets local paths for the bot)
        * Pick Bot Service Daemon: (Currently utilizes RunIt and Supervisor, choose which you prefer)
    * External Items Configuration
        * Enter Cookbook Name (If different): (If you fork this cookbook, just set the cookbook name to whatever you want)
        * Enter Cookbook Git Clone URL (If different): (if forked or moved, just enter the new clone url)
        * Enter Cookbook Git Branch to use (If different): (If needing to test a branch before meging, bersk will pull that branch)
        * Enter User Data Script URL (If different):
    * Lets Encrypt (SSL) Configuration
        * Pick Cert Type: (Unless deploying for real, choose stage. Production has an api limit)
        * Enter Email for Cert Notices: (should auto-renew, but lets you know to be sure to check that the cert doesn't expire on you)
* Choose whatever advanced options you choose (none are required); click next
* Check the `I acknowledge that this template might cause AWS CloudFormation to create IAM resources.` portion
* Click Create

# Creation Items
* SSL Secured Pagerduty Webhook Endpoint: $botname.domain.com/incident (will be in the output tab of cloudformation)
* Incident Bot; Specialized configured bot to handle you incident via pagerduty & slack

# Troubleshooting
Always check the log locations first!

* User Data Script Log: /var/log/user-data.log
* Bot Log Location: /var/log/bot/current
* Redis Log Location (default): /var/log/redis/redis-server.log

# Environment Variables

When using runit check the contents of the files in `/etc/sv/bot/env` that they are set properly.

## Webhook Endpoint
Endpoint Issues specifics to the Webhook/Http listener

* Certificate Shows invalid
    * Nginx may have not restarted after generating the real cert, restart nginx
    * note: Service may show down, but `ps -ef | grep nginx` may return rouge processes that need to be killed
