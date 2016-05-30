#!/bin/bash

script_name=$(basename "$0")
usage ()
{
cat << EOF
usage $script_name OPTIONS

Create an AWS environment running openshift 3.2 under RHEL 7.2

EXAMPLE:
$script_name --rhuser <username> --rhpass <password> --rhpool <poolid> --cluster <true / false> --lpc <true / false> --awsrhid <rhelImageId> --awsregion <Aws region>
OPTIONS EXPLAINED: 
rhuser = your redhat user it
rhpass = your redhat password 
rhpool = from from "subscription-manager list --avalibale --all" (take the repo with openshift in it)
cluster = do you want a clustered AWS setup with loadbalancer, multiple infranodes and routes then this is the option for you (currently under construction)
lpc = Do you want to have a mgmt server where all commands can be run from, then this is the option for you otherwise i will run it all from you local computer.
awsrhid = this is the ID from your AWS console LAUNCH Instance you can pick Red Hat Enterprise Linux 7.2 (HVM), SSD Volume Type - ami-775e4f16 (take the ami- number and insert here)
awsregion = use one of the regions listed in amazon. aws ec2 describe-regions will list something like: 

REGIONS	ec2.eu-west-1.amazonaws.com	eu-west-1
REGIONS	ec2.ap-southeast-1.amazonaws.com	ap-southeast-1
REGIONS	ec2.ap-southeast-2.amazonaws.com	ap-southeast-2
REGIONS	ec2.eu-central-1.amazonaws.com	eu-central-1
REGIONS	ec2.ap-northeast-2.amazonaws.com	ap-northeast-2
REGIONS	ec2.ap-northeast-1.amazonaws.com	ap-northeast-1
REGIONS	ec2.us-east-1.amazonaws.com	us-east-1
REGIONS	ec2.sa-east-1.amazonaws.com	sa-east-1
REGIONS	ec2.us-west-1.amazonaws.com	us-west-1
REGIONS	ec2.us-west-2.amazonaws.com	us-west-2


EOF
exit 1
}

awsmiss ()
{
cat << EOF
I cant find AWS Client installed on your computer or you forgot to configure aws. 
For installation you can do the following:  

on fedora you can do a "yum install aws"

others: 

curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip"

unzip awscli-bundle.zip

sudo ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws


then you do a aws configure and insert the secrets you have created in AWS otherwise this script wont work. 

$ aws configure
AWS Access Key ID [****************A]: 
AWS Secret Access Key [****************1]: 
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



EOF
exit 1
}


OPTIONS=`getopt -o h -l help -l rhuser: -l rhpass: -l rhpool: -l cluster: -l lpc: -l awsrhid: -l awsregion: -- "$@"`

if [ $? != 0 ]; then
        usage
fi

RHUSER=""
RHPASS=""
RHPOOL=""
CLUSTER=""
LPC=""
AWSRHID=""
AWSREGION=""

eval set -- "$OPTIONS"

while true; do
case "$1" in
        -h|--help) usage;;
        --rhuser) RHUSER=$2; shift 2;;
        --rhpass) RHPASS=$2; shift 2;;
        --rhpool) RHPOOL=$2; shift 2;;
	--cluster) CLUSTER=$2; shift 2;;
	--lpc) LPC=$2; shift 2;;
	--awsrhid) AWSRHID=$2; shift 2;;
	--awsregion) AWSREGION=$2; shift 2;;
        --) shift; break;;
        *) usage;;
esac
done
if [ ! -f /usr/local/bin/aws ]; then
	awsmiss
fi

if [ -z "$RHUSER" ]; then
        usage
fi

if [ -z "$RHPASS" ]; then
        usage
fi

if [ -z "$RHPOOL" ]; then 
	usage
fi

if [ -z "$CLUSTER" ]; then
	usage
fi

if [ -z "$LPC" ]; then
	usage
fi

if [ -z "$AWSRHID" ]; then
	usage
fi

if [ -z "$AWSREGION" ]; then
	usage
fi

