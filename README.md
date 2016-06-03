# openshift-aws-allinone
This script is created to help deploy a full and ready AWS environment for users unfamiliar with AWS and Openshift.

Usage: 
Download All files in this git repo. 

Make sure you have insatlled the AWS CLI

On Fedora run "dnf install aws"
On RHEL run: 
curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip"

unzip awscli-bundle.zip

sudo ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws

The script is not that smart yet so it will only find the aws binary in /usr/local/bin/aws

Setup AWS: 

hen you do a aws configure and insert the secrets you have created in AWS otherwise this script wont work. 

$ aws configure
AWS Access Key ID [<somenumbers>]: 
AWS Secret Access Key [<Somenumbers>]: 
Default region name [us-west-2]: 
Default output format [text]: 

If you dont know how to get your keys here is the manual.
In AWS console: 
Open the Identity and Access Management (IAM) console.
From the navigation menu, click Users.
Select your IAM user name.
Click User Actions, and then click Manage Access Keys.
Click Create Access Key.
Select Show User Security Credentials

Regions are displayed here: 

REGIONS        ec2.eu-west-1.amazonaws.com     eu-west-1
REGIONS        ec2.ap-southeast-1.amazonaws.com        ap-southeast-1
REGIONS        ec2.ap-southeast-2.amazonaws.com        ap-southeast-2
REGIONS        ec2.eu-central-1.amazonaws.com  eu-central-1
REGIONS        ec2.ap-northeast-2.amazonaws.com        ap-northeast-2
REGIONS        ec2.ap-northeast-1.amazonaws.com        ap-northeast-1
REGIONS        ec2.us-east-1.amazonaws.com     us-east-1
REGIONS        ec2.sa-east-1.amazonaws.com     sa-east-1
REGIONS        ec2.us-west-1.amazonaws.com     us-west-1
REGIONS        ec2.us-west-2.amazonaws.com     us-west-2

rhpool = from from "subscription-manager list --avalibale --all" (take the repo with openshift in it its the long number)

awsrhid = this is the ID from your AWS console LAUNCH Instance you can pick Red Hat Enterprise Linux 7.2 (HVM), SSD Volume Type - ami-775e4f16 (take the ami- number and insert here)

awsregion = use one of the regions listed

dnsopt = dnsname of router and servers could be cloud.pfy.dk cloud.rhcloud.dk or cloud.google.com depending on what you own.



== 
awsoes.sh --rhuser <RHN USERNAME> --rhpool=<RHNPOOLID>  --cluster false(pick false here cluster is not there yet) --clusterid <Name of your setup>  --awsrhid <AWS Image name> --awsregion <AWS Region> --dnsopt=<DNS DOMAIN>

That is it your aws environment will now spin up this will take some time.
If it hangs during a server update (patch) try and press enter, it could simply be a glitch in your ssh connection. 

