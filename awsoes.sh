#!/bin/bash
#exp; <kborup at redhat.com> 
#Use at own risk, there are parts that does not work yet. 
#Development started the 25th of May. 
#Released under GPL. 

script_name=$(basename "$0")
usage ()
{
cat << EOF
usage $script_name OPTIONS

Create an AWS environment running openshift 3.2 under RHEL 7.2

EXAMPLE:
$script_name --rhuser <username> --rhpool <poolid> --cluster true / false> --awsrhid <rhelImageId> --awsregion <Aws region> --dnsopt=dnsname --awsdnszone <ZONEID> --awsdns= true/false
OPTIONS EXPLAINED: 
rhuser = your redhat user it
rhpass = your redhat password 
rhpool = from from "subscription-manager list --avalibale --all" (take the repo with openshift in it)
cluster = do you want a clustered AWS setup with loadbalancer, multiple infranodes and routes then this is the option for you (currently under construction)
awsrhid = this is the ID from your AWS console LAUNCH Instance you can pick Red Hat Enterprise Linux 7.2 (HVM), SSD Volume Type - ami-775e4f16 (take the ami- number and insert here)
awsregion = use one of the regions listed in amazon. aws ec2 describe-regions will list something like: 
dnsopt = dnsname of router and servers could be cloud.pfy.dk cloud.redhat.com or cloud.google.com depending on what you own.

#REGIONS	ec2.eu-west-1.amazonaws.com	eu-west-1
#REGIONS	ec2.ap-southeast-1.amazonaws.com	ap-southeast-1
#REGIONS	ec2.ap-southeast-2.amazonaws.com	ap-southeast-2
#REGIONS	ec2.eu-central-1.amazonaws.com	eu-central-1
#REGIONS	ec2.ap-northeast-2.amazonaws.com	ap-northeast-2
#REGIONS	ec2.ap-northeast-1.amazonaws.com	ap-northeast-1
#REGIONS	ec2.us-east-1.amazonaws.com	us-east-1
#REGIONS	ec2.sa-east-1.amazonaws.com	sa-east-1
#REGIONS	ec2.us-west-1.amazonaws.com	us-west-1
#REGIONS	ec2.us-west-2.amazonaws.com	us-west-2


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


OPTIONS=`getopt -o h -l help -l rhuser: -l rhpool: -l cluster: -l clusterid: -l awsrhid: -l awsregion: -l dnsopt: -l awsdns: -l awsdnszone: -- "$@"`

if [ $? != 0 ]; then
        usage
fi

RHUSER=""
RHPASS=""
RHPOOL=""
CLUSTER=""
CLUSTERID=""
AWSRHID=""
AWSREGION=""
DNSOPT=""
AWSDNS=""
AWSDNSZONE=""

eval set -- "$OPTIONS"

while true; do
case "$1" in
        -h|--help) usage;;
        --rhuser) RHUSER=$2; shift 2;;
        --rhpool) RHPOOL=$2; shift 2;;
	--cluster) CLUSTER=$2; shift 2;;
	--clusterid) CLUSTERID=$2; shift 2;;
	--awsrhid) AWSRHID=$2; shift 2;;
	--awsregion) AWSREGION=$2; shift 2;;
	--dnsopt) DNSOPT=$2; shift 2;;
	--awsdns) AWSDNS=$2; shift 2;;
	--awsdnszone) AWSDNSZONE=$2; shift 2;;
        --) shift; break;;
        *) usage;;
esac
done
if [ $AWSDNS == true ]; then
if [ -z "$AWSDNSZONE" ]; then
usage
fi
fi 

if [ ! -f /usr/local/bin/aws ]; then
	awsmiss
fi

if [ -z "$RHUSER" ]; then
        usage
fi

echo "Please enter you password for RHN";
stty -echo
read RHPASS;
stty echo

if [ -z "$RHPOOL|$CLUSTER|$CLUSTERID|$AWSRHID|$AWSREGION|$DNSOPT|$AWSDNS" ]; then 
	usage
fi

echo -n "Do you have a passwordless ssh key for amazon (y/n)? "
read answer
if echo "$answer" | grep -iq "^y" ;then
    echo "type in keyname that have access to amazon alrady"
    read keyname
    KEYNAME=$keyname 
else
    echo "Creating a key for amazon and uploading it"
	echo "name your key no spaces"
	read keyname	
	KEYNAME=$keyname
	aws ec2 create-key-pair --key-name ${KEYNAME} --query 'KeyMaterial' --output text > ~/.ssh/${KEYNAME}.pem
	chmod 600 ~/.ssh/${KEYNAME}.pem
fi

echo "Creating VPC Network"
VPCID=`aws ec2 create-vpc --cidr-block 192.168.0.0/24 --output text | awk '{print $7}'`
aws ec2 create-tags --resource $VPCID --tags Key=deployment,Value=paas Key=Name,Value=${CLUSTERID}_vpc
aws ec2 modify-vpc-attribute --vpc-id $VPCID --enable-dns-support "{\"Value\":true}"
aws ec2 modify-vpc-attribute --vpc-id $VPCID --enable-dns-hostnames "{\"Value\":true}"
echo "VPC Created"

echo "Creating Gateway"
INTERNETGWID=`aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text`
aws ec2 create-tags --resource $INTERNETGWID --tags Key=deployment,Value=paas Key=type,Value=gateway Key=Name,Value=${CLUSTERID}_DMZSubnet
aws ec2 attach-internet-gateway --internet-gateway-id $INTERNETGWID --vpc-id $VPCID
echo "Gateway Created"

echo "Setting Region IDS"
REGIONIDS=`aws ec2 describe-availability-zones --region ${AWSREGION}  --output json | grep ZoneName | xargs`
AZ1=`echo $REGIONIDS | awk '{print $2}'`
AZ2=`echo $REGIONIDS | awk '{print $4}'`
AZ3=`echo $REGIONIDS | awk '{print $6}'`

echo "Creating SubnetID"
DMZSUBNETID=`aws ec2 create-subnet --vpc-id $VPCID --cidr-block 192.168.0.0/26  --availability-zone $AZ1 --query 'Subnet.SubnetId' --output text`
aws ec2 create-tags --resource $DMZSUBNETID --tags Key=deployment,Value=paas Key=type,Value=subnet Key=Name,Value=${CLUSTERID}_DMZSubnet
INTERNALSUBNETID=`aws ec2 create-subnet --vpc-id $VPCID --cidr-block 192.168.0.128/26 --availability-zone $AZ1 --query 'Subnet.SubnetId' --output text`
aws ec2 create-tags --resource $INTERNALSUBNETID --tags Key=deployment,Value=paas Key=type,Value=subnet Key=Name,Value=${CLUSTERID}_INTERNALSubnet
EXTERNALROUTETABLEID=`aws ec2 create-route-table --vpc-id $VPCID --query 'RouteTable.RouteTableId' --output text`
echo "Subnet ID Created"

echo "Creating Route"
aws ec2 create-route --route-table-id $EXTERNALROUTETABLEID --destination-cidr-block 0.0.0.0/0 --gateway-id $INTERNETGWID
aws ec2 associate-route-table --route-table-id $EXTERNALROUTETABLEID --subnet-id $DMZSUBNETID
aws ec2 associate-route-table --route-table-id $EXTERNALROUTETABLEID --subnet-id $INTERNALSUBNETID
echo "Done Creating Routes"

#Service groups are hardcoded should we change that ?
MASGNAME=mastersg
INSGNAME=infrasg
NSGNAME=nodesg
NFSNAME=nfssg

echo "Creating security Groups"
MASTERSGID=`aws ec2 create-security-group --group-name $MASGNAME --description "Masters Security Group" --vpc-id $VPCID --query 'GroupId' --output text`
aws ec2 create-tags --resource $MASTERSGID --tags Key=deployment,Value=pass Key=type,Value=SecGroup Key=Name,Value=${CLUSTERID}_${MASGNAME}
INFRASGID=`aws ec2 create-security-group --group-name $INSGNAME --description "Infra Nodes Security Group" --vpc-id $VPCID --query 'GroupId' --output text`
aws ec2 create-tags --resource $INFRASGID --tags Key=deployment,Value=paas Key=type,Value=SecGroup Key=Name,Value=${CLUSTERID}_${INSGNAME}
NODESGID=`aws ec2 create-security-group --group-name $NSGNAME --description "Compute Nodes Security Group" --vpc-id $VPCID --query 'GroupId' --output text`
aws ec2 create-tags --resource $NODESGID --tags Key=deployment,Value=paas Key=type,Value=SecGroup Key=Name,Value=${CLUSTERID}_${NSSGNAME}
NFSSGID=`aws ec2 create-security-group --group-name $NFSNAME --description "NFS Security Group" --vpc-id $VPCID --query 'GroupId' --output text`
aws ec2 create-tags --resource $NFSSGID --tags Key=deployment,Value=paas Key=type,Value=SecGroup Key=Name,Value=${CLUSTERID}_${NFSNAME}
echo "Done Creating Security Groups"

echo "Creating firewalls as per version 3.1 will be updated before final release"

aws ec2 authorize-security-group-ingress --group-id $MASTERSGID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $MASTERSGID --protocol tcp --port 8443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $MASTERSGID --protocol udp --port 4789 --source-group $NODESGID
aws ec2 authorize-security-group-ingress --group-id $MASTERSGID --protocol tcp --port 8443 --source-group $NODESGID
aws ec2 authorize-security-group-ingress --group-id $MASTERSGID --protocol udp --port 8053 --source-group $NODESGID


aws ec2 authorize-security-group-ingress --group-id $MASTERSGID --protocol tcp --port 53 --source-group $NODESGID
aws ec2 authorize-security-group-ingress --group-id $MASTERSGID --protocol udp --port 53 --source-group $NODESGID
aws ec2 authorize-security-group-ingress --group-id $MASTERSGID --protocol tcp --port 53 --source-group $INFRASGID
aws ec2 authorize-security-group-ingress --group-id $MASTERSGID --protocol udp --port 53 --source-group $INFRASGID

aws ec2 authorize-security-group-ingress --group-id $INFRASGID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $INFRASGID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $INFRASGID --protocol tcp --port 443 --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress --group-id $NODESGID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $NODESGID --protocol tcp --port 10250 --source-group $MASTERSGID
aws ec2 authorize-security-group-ingress --group-id $NODESGID --protocol udp --port 4789 --source-group $MASTERSGID
aws ec2 authorize-security-group-ingress --group-id $NODESGID --protocol udp --port 4789 --source-group $NODESGID

#Setting NFS.
aws ec2 authorize-security-group-ingress --group-id $NFSSGID --protocol tcp --port 111 --source-group $NODESGID
aws ec2 authorize-security-group-ingress --group-id $NFSSGID --protocol tcp --port 2049 --source-group $NODESGID
aws ec2 authorize-security-group-ingress --group-id $NFSSGID --protocol tcp --port 20048 --source-group $NODESGID
aws ec2 authorize-security-group-ingress --group-id $NFSSGID --protocol tcp --port 50825 --source-group $NODESGID
aws ec2 authorize-security-group-ingress --group-id $NFSSGID --protocol tcp --port 53248 --source-group $NODESGID
aws ec2 authorize-security-group-ingress --group-id $NFSSGID --protocol udp --port 111 --source-group $NODESGID
aws ec2 authorize-security-group-ingress --group-id $NFSSGID --protocol udp --port 2049 --source-group $NODESGID
aws ec2 authorize-security-group-ingress --group-id $NFSSGID --protocol udp --port 20048 --source-group $NODESGID
aws ec2 authorize-security-group-ingress --group-id $NFSSGID --protocol udp --port 50825 --source-group $NODESGID
aws ec2 authorize-security-group-ingress --group-id $NFSSGID --protocol udp --port 53248 --source-group $NODESGID
aws ec2 authorize-security-group-ingress --group-id $NFSSGID --protocol tcp --port 22 --cidr 0.0.0.0/0


echo "Setting AWS RedHat Image Name"
AMIID=`echo $AWSRHID`

if [ $CLUSTER = true ]; then
echo "Creating Multiple cluster nodes"
MASTER00ID=`aws ec2 run-instances --image-id $AMIID  --count 1 --instance-type t2.small --key-name $KEYNAME --security-group-ids $MASTERSGID --subnet-id $DMZSUBNETID --associate-public-ip-address --query Instances[*].InstanceId --output text`
aws ec2 create-tags --resource $MASTER00ID --tags Key=deployment,Value=paas Key=type,Value=instance Key=Name,Value=${CLUSTERID}_master00 Key=clusterid,Value=${CLUSTERID}
MASTER00PUBLICDNS=`aws ec2 describe-instances --instance-ids $MASTER00ID --query Reservations[*].Instances[*].[PublicDnsName] --output text`
SHORTMASTER00PUBLICDNS=master00.${DNSOPT}
MASTER00PUBLICIP=`aws ec2 describe-instances --instance-ids $MASTER00ID --query Reservations[*].Instances[*].[PublicIpAddress] --output text`
MASTER00PRIVATEIP=`aws ec2 describe-instances --instance-ids $MASTER00ID --query Reservations[*].Instances[*].[PrivateIpAddress] --output text`

MASTER01ID=`aws ec2 run-instances --image-id $AMIID  --count 1 --instance-type t2.small --key-name $KEYNAME --security-group-ids $MASTERSGID --subnet-id $DMZSUBNETID --associate-public-ip-address --query Instances[*].InstanceId --output text`
aws ec2 create-tags --resource $MASTER01ID --tags Key=deployment,Value=paas Key=type,Value=instance Key=Name,Value=${CLUSTERID}_master00 Key=clusterid,Value=${CLUSTERID}
MASTER01PUBLICDNS=`aws ec2 describe-instances --instance-ids $MASTER01ID --query Reservations[*].Instances[*].[PublicDnsName] --output text`
SHORTMASTER01PUBLICDNS=master01.${DNSOPT}
MASTER01PUBLICIP=`aws ec2 describe-instances --instance-ids $MASTER01ID --query Reservations[*].Instances[*].[PublicIpAddress] --output text`
MASTER01PRIVATEIP=`aws ec2 describe-instances --instance-ids $MASTER01ID --query Reservations[*].Instances[*].[PrivateIpAddress] --output text`

MASTER02ID=`aws ec2 run-instances --image-id $AMIID  --count 1 --instance-type t2.small --key-name $KEYNAME --security-group-ids $MASTERSGID --subnet-id $DMZSUBNETID --associate-public-ip-address --query Instances[*].InstanceId --output text`
aws ec2 create-tags --resource $MASTER02ID --tags Key=deployment,Value=paas Key=type,Value=instance Key=Name,Value=${CLUSTERID}_master00 Key=clusterid,Value=${CLUSTERID}
MASTER02PUBLICDNS=`aws ec2 describe-instances --instance-ids $MASTER02ID --query Reservations[*].Instances[*].[PublicDnsName] --output text`
SHORTMASTER02PUBLICDNS=master02.${DNSOPT}
MASTER02PUBLICIP=`aws ec2 describe-instances --instance-ids $MASTER02ID --query Reservations[*].Instances[*].[PublicIpAddress] --output text`
MASTER02PRIVATEIP=`aws ec2 describe-instances --instance-ids $MASTER02ID --query Reservations[*].Instances[*].[PrivateIpAddress] --output text`

LOAD00ID=`aws ec2 run-instances --image-id $AMIID  --count 1 --instance-type t2.small --key-name $KEYNAME --security-group-ids $MASTERSGID --subnet-id $DMZSUBNETID --associate-public-ip-address --query Instances[*].InstanceId --output text`
aws ec2 create-tags --resource $LOAD00ID --tags Key=deployment,Value=paas Key=type,Value=instance Key=Name,Value=${CLUSTERID}_master00 Key=clusterid,Value=${CLUSTERID}
LOAD00PUBLICDNS=`aws ec2 describe-instances --instance-ids $LOAD00ID --query Reservations[*].Instances[*].[PublicDnsName] --output text`
SHORTLOAD00PUBLICDNS=loadbalancer.${DNSOPT}
LOAD00PUBLICIP=`aws ec2 describe-instances --instance-ids $LOAD00ID --query Reservations[*].Instances[*].[PublicIpAddress] --output text`
LOAD00PRIVATEIP=`aws ec2 describe-instances --instance-ids $LOAD00ID --query Reservations[*].Instances[*].[PrivateIpAddress] --output text`



else

echo "Creating single master node" 
MASTER00ID=`aws ec2 run-instances --image-id $AMIID  --count 1 --instance-type t2.small --key-name $KEYNAME --security-group-ids $MASTERSGID --subnet-id $DMZSUBNETID --associate-public-ip-address --query Instances[*].InstanceId --output text`
aws ec2 create-tags --resource $MASTER00ID --tags Key=deployment,Value=paas Key=type,Value=instance Key=Name,Value=${CLUSTERID}_master00 Key=clusterid,Value=${CLUSTERID}
MASTER00PUBLICDNS=`aws ec2 describe-instances --instance-ids $MASTER00ID --query Reservations[*].Instances[*].[PublicDnsName] --output text`
SHORTMASTER00PUBLICDNS=master00.${DNSOPT}
MASTER00PUBLICIP=`aws ec2 describe-instances --instance-ids $MASTER00ID --query Reservations[*].Instances[*].[PublicIpAddress] --output text`
MASTER00PRIVATEIP=`aws ec2 describe-instances --instance-ids $MASTER00ID --query Reservations[*].Instances[*].[PrivateIpAddress] --output text`
fi


echo "Creating MGMT Node"
LAB00ID=`aws ec2 run-instances --image-id $AMIID  --count 1 --instance-type t2.small --key-name ${KEYNAME} --security-group-ids $MASTERSGID --subnet-id $DMZSUBNETID --associate-public-ip-address --query Instances[*].InstanceId --output text`
aws ec2 create-tags --resource $LAB00ID --tags --tags Key=deployment,Value=paas Key=type,Value=instance Key=Name,Value=${CLUSTERID}_lab00 Key=clusterid,Value=${CLUSTERID}
LAB00PUBLICDNS=`aws ec2 describe-instances --instance-ids $LAB00ID --query Reservations[*].Instances[*].[PublicDnsName] --output text`
SHORTLAB00PUBLICDNS=lab.${DNSOPT}
LAB00PUBLICIP=`aws ec2 describe-instances --instance-ids $LAB00ID --query Reservations[*].Instances[*].[PublicIpAddress] --output text`
LAB00PRIVATEIP=`aws ec2 describe-instances --instance-ids $LAB00ID --query Reservations[*].Instances[*].[PrivateIpAddress] --output text`
echo "sleeping while we wait for node to become ready its in the cloud!!"
sleep 3m

ssh -ti ~/.ssh/${KEYNAME}.pem ec2-user@${LAB00PUBLICIP} "
sudo sudo rm  /etc/yum.repos.d/*
sudo subscription-manager register --username=${RHUSER} --password=${RHPASS}
sudo subscription-manager attach --pool=${RHPOOL}
sudo subscription-manager repos --disable='*'
sudo subscription-manager repos --enable=rhel-7-server-rpms --enable=rhel-7-server-extras-rpms --enable=rhel-7-server-ose-3.2-rpms
sudo yum update -y
" ; 

 
echo "Creating nodes"
INSTANCESTEMP=`aws ec2 run-instances --image-id $AMIID  --count 2 --instance-type t2.small --key-name ${KEYNAME} --security-group-ids $NODESGID --subnet-id $DMZSUBNETID --associate-public-ip-address --query Instances[*].InstanceId --output text`

export NODE00ID=`echo $INSTANCESTEMP | awk '{print $1}'`
export NODE01ID=`echo $INSTANCESTEMP | awk '{print $2}'`

aws ec2 create-tags --resource $NODE00ID --tags Key=deployment,Value=paas Key=type,Value=instance Key=Name,Value=${CLUSTERID}_node00 Key=clusterid,Value=${CLUSTERID}
aws ec2 create-tags --resource $NODE01ID --tags Key=deployment,Value=paas Key=type,Value=instance Key=Name,Value=${CLUSTERID}_node01 Key=clusterid,Value=${CLUSTERID}

NODE00PUBLICDNS=`aws ec2 describe-instances --instance-ids $NODE00ID --query Reservations[*].Instances[*].[PublicDnsName] --output text`
SHORTNODE00PUBLICDNS=node00.${DNSOPT}
NODE00PRIVATEIP=`aws ec2 describe-instances --instance-ids $NODE00ID --query Reservations[*].Instances[*].[PrivateIpAddress] --output text`
NODE00PUBLICIP=`aws ec2 describe-instances --instance-ids $NODE00ID --query Reservations[*].Instances[*].[PublicIpAddress] --output text`


NODE01PUBLICDNS=`aws ec2 describe-instances --instance-ids $NODE01ID --query Reservations[*].Instances[*].[PublicDnsName] --output text`
SHORTNODE01PUBLICDNS=node01.${DNSOPT}
NODE01PRIVATEIP=`aws ec2 describe-instances --instance-ids $NODE01ID --query Reservations[*].Instances[*].[PrivateIpAddress] --output text`
NODE01PUBLICIP=`aws ec2 describe-instances --instance-ids $NODE01ID --query Reservations[*].Instances[*].[PublicIpAddress] --output text`

if [ $CLUSTER = true ]; then 
echo "Creating two infranodes"
INFRATEMP=`aws ec2 run-instances --image-id $AMIID  --count 2 --instance-type t2.small --key-name ${KEYNAME} --security-group-ids $NODESGID $INFRASGID--subnet-id $DMZSUBNETID --associate-public-ip-address --query Instances[*].InstanceId --output text`
export INFRA00ID=`echo $INSTANCESTEMP | awk '{print $1}'`
export INFRA01ID=`echo $INSTANCESTEMP | awk '{print $2}'`
aws ec2 create-tags --resource $INFRA00ID --tags Key=deployment,Value=paas Key=type,Value=instance Key=Name,Value=${CLUSTERID}_infranode00 Key=clusterid,Value=${CLUSTERID}
aws ec2 create-tags --resource $INFRA01ID --tags Key=deployment,Value=paas Key=type,Value=instance Key=Name,Value=${CLUSTERID}_infranode01 Key=clusterid,Value=${CLUSTERID}

INFRA00PUBLICDNS=`aws ec2 describe-instances --instance-ids $INFRA00ID --query Reservations[*].Instances[*].[PublicDnsName] --output text`
SHORTINFRA00PUBLICDNS=infranode00.${DNSOPT}
INFRA00PRIVATEIP=`aws ec2 describe-instances --instance-ids $INFRA00ID --query Reservations[*].Instances[*].[PrivateIpAddress] --output text`
INFRA00PUBLICIP=`aws ec2 describe-instances --instance-ids $INFRA00ID --query Reservations[*].Instances[*].[PublicIpAddress] --output text`

INFRA01PUBLICDNS=`aws ec2 describe-instances --instance-ids $INFRA01ID --query Reservations[*].Instances[*].[PublicDnsName] --output text`
SHORTINFRA01PUBLICDNS=infranode01.${DNSOPT}
INFRA01PRIVATEIP=`aws ec2 describe-instances --instance-ids $INFRA01ID --query Reservations[*].Instances[*].[PrivateIpAddress] --output text`
INFRA01PUBLICIP=`aws ec2 describe-instances --instance-ids $INFRA01ID --query Reservations[*].Instances[*].[PublicIpAddress] --output text`

else

echo "Creating Infra Node"
INFRANODE00ID=`aws ec2 run-instances --image-id $AMIID  --count 1 --instance-type t2.small --key-name ${KEYNAME} --security-group-ids $INFRASGID $NODESGID --subnet-id $DMZSUBNETID --associate-public-ip-address --query Instances[*].InstanceId --output text`
aws ec2 create-tags --resource $INFRANODE00ID --tags Key=deployment,Value=paas Key=type,Value=instance Key=Name,Value=${CLUSTERID}_infranode00 Key=clusterid,Value=${CLUSTERID}

INFRANODE00PUBLICDNS=`aws ec2 describe-instances --instance-ids $INFRANODE00ID --query Reservations[*].Instances[*].[PublicDnsName] --output text`
SHORTINFRANODE00PUBLICDNS=infranode00.${DNSOPT}
INFRANODE00PRIVATEIP=`aws ec2 describe-instances --instance-ids $INFRANODE00ID --query Reservations[*].Instances[*].[PrivateIpAddress] --output text`
INFRANODE00PUBLICIP=`aws ec2 describe-instances --instance-ids $INFRANODE00ID --query Reservations[*].Instances[*].[PublicIpAddress] --output text`
fi

echo "Creating NFS Node and Adding an extra disk"

NFSNODE00ID=`aws ec2 run-instances --image-id $AMIID  --count 1 --instance-type t2.small --key-name ${KEYNAME} --security-group-ids $NFSSGID --subnet-id $DMZSUBNETID --associate-public-ip-address --query Instances[*].InstanceId --output text`
SHORTNFSNODE00DNS=nfs00.${DNSOPT}
NFS00PRIVATEIP=`aws ec2 describe-instances --instance-ids $NFSNODE00ID --query Reservations[*].Instances[*].[PrivateIpAddress] --output text`
NFS00PUBLICIP=`aws ec2 describe-instances --instance-ids $NFSNODE00ID --query Reservations[*].Instances[*].[PublicIpAddress] --output text`
aws ec2 create-tags --resource $NFSNODE00ID --tags Key=deployment,Value=paas Key=type,Value=instance Key=Name,Value=${CLUSTERID}_nfsnode00 Key=clusterid,Value=${CLUSTERID}
NFSVOL=`aws ec2 create-volume --region $AWSREGION --availability-zone $AZ1 --size 20 --volume-type gp2 | awk '{print $7}'`
echo "sleeping 4 minutts waiting for the disk to be ready"
sleep 4m 
aws ec2 attach-volume --volume-id $NFSVOL --instance-id $NFSNODE00ID --device /dev/sdb 

if [ $CLUSTER = true ]; then 
echo "Setting up RHN on nodes"
nodes="${MASTER00PUBLICDNS} ${MASTER01PUBLICDNS} ${MASTER02PUBLICDNS} ${NODE00PUBLICDNS} ${NODE01PUBLICDNS} ${INFRA00PUBLICDNS} ${INFRA01PUBLICDNS} ${LOAD00PUBLICDNS}"
else

echo "Setting up RHN on nodes"
nodes="${MASTER00PUBLICDNS} ${INFRANODE00PUBLICDNS} ${NODE00PUBLICDNS} ${NODE01PUBLICDNS}"
fi 

for node in $nodes ; do ssh -ti ~/.ssh/${KEYNAME}.pem ec2-user@${node} "
echo Configure the Repositories on ${node} if any of this looks to hang press ENTER
sudo sudo rm  /etc/yum.repos.d/*
sudo subscription-manager register --username=${RHUSER} --password=${RHPASS}
sudo subscription-manager attach --pool=${RHPOOL}
sudo subscription-manager repos --disable='*'
sudo subscription-manager repos --enable="rhel-7-server-rpms" --enable="rhel-7-server-extras-rpms" --enable="rhel-7-server-ose-3.2-rpms"
sudo yum -y install "wget git net-tools bind-utils iptables-services bridge-utils bash-completion"
sudo yum update -y
echo Installing Docker on ${node}
sudo yum install docker -y
sudo cp /etc/sysconfig/docker /etc/sysconfig/docker.original
sudo sed -i 's/--selinux-enabled/--selinux-enabled --insecure-registry 172.30.0.0\/0/' /etc/sysconfig/docker 
sudo reboot
" ; done
echo "sleeping until all nodes are back up"
sleep 5m



SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
echo "Creating var file"
chmod 700 $DIR/vars.sh
echo > $DIR/vars.sh

for x in DNSOPT RHNUSER MASTER00PRIVATIP MASTER00PUBLICIP NODE00PRIVATEIP NODE00PUBLICIP NODE01PRIVATEIP NODE01PUBLICIP LAB00PUBLICIP LAB00PRIVATEIP INFRANODE00PUBLICIP INFRANODE00PRIVATEIP MASTER00PUBLICDNS NODE00PUBLICDNS NODE01PUBLICDNS LAB00PUBLICDNS INFRANODE00PUBLICDNS AWSREGION AZ1 NFS00PUBLICIP NFS00PUBLICDNS NFS00PRIVATEIP MASTER01PUBLICDNS MASTER01PUBLICIP MASTER01PRIVATEIP MASTER02PUBLICDNS MASTER02PRIVATEIP MASTER02PUBLICIP INFRA00PUBLICDNS INFRA00PRIVATEIP INFRA00PUBLICIP INFRA01PUBLICDNS INFRA01PRIVATEIP INFRA01PUBLICIP LOAD00PUBLICDNS LOAD00PRIVATEIP LOAD00PUBLICIP ; do set | grep $x | sed s/x=$x// | grep -v ^$ | grep -v name  >> $DIR/vars.sh ; done


if [ $AWSDNS == true ]; then
cat << EOF > NODE00.json
{
    "Comment": "NODE00",
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "node00.${DNSOPT}.",
                "Type": "A",
                "TTL": 30,
                "ResourceRecords": [
                    {
                        "Value": "${NODE00PUBLICIP}"
                    }
                ]
            }
        }
    ]
}
EOF
cat << EOF > NODE01.json
{
    "Comment": "NODE01",
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "node01.${DNSOPT}.",
                "Type": "A",
                "TTL": 30,
                "ResourceRecords": [
                    {
                        "Value": "${NODE01PUBLICIP}"
                    }
                ]
            }
        }
    ]
}
EOF
cat << EOF > MASTER00.json
{
    "Comment": "MASTER00",
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "master00.${DNSOPT}.",
                "Type": "A",
                "TTL": 30,
                "ResourceRecords": [
                    {
                        "Value": "${MASTER00PUBLICIP}"
                    }
                ]
            }
        }
    ]
}
EOF
cat << EOF > NFS.json
{
    "Comment": "NFS",
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "nfs.${DNSOPT}.",
                "Type": "A",
                "TTL": 30,
                "ResourceRecords": [
                    {
                        "Value": "${NFS00PUBLICIP}"
                    }
                ]
            }
        }
    ]
}
EOF
cat << EOF > LAB.json
{
    "Comment": "LAB",
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "lab.${DNSOPT}.",
                "Type": "A",
                "TTL": 30,
                "ResourceRecords": [
                    {
                        "Value": "${LAB00PUBLICIP}"
                    }
                ]
            }
        }
    ]
}
EOF
cat << EOF > INFRANODE00.json
{
    "Comment": "INFRANODE00",
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "infranode00.${DNSOPT}.",
                "Type": "A",
                "TTL": 30,
                "ResourceRecords": [
                    {
                        "Value": "${INFRANODE00PUBLICIP}"
                    }
                ]
            }
        }
    ]
}
EOF

cat << EOF > wildcard.json
{
    "Comment": "wildcard",
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "*.${DNSOPT}.",
                "Type": "A",
                "TTL": 30,
                "ResourceRecords": [
                    {
                        "Value": "${INFRANODE00PUBLICIP}"
                    }
                ]
            }
        }
    ]
}
EOF


for x in *.json
do
aws route53 change-resource-record-sets --hosted-zone-id $AWSDNSZONE --change-batch file://$x;
done

else 
echo master00.${DNSOPT}
echo $MASTER00PUBLICIP

echo nfs.${DNSOPT}
echo $NFS00PUBLICIP

echo infranode00.${DNSOPT}
echo $INFRANODE00PUBLICIP

echo node00.${DNSOPT}
echo $NODE00PUBLICIP

echo node01.${DNSOPT}
echo $NODE01PUBLICIP

echo lab.${DNSOPT}
echo $LAB00PUBLICIP

echo *.${DNSOPT}
echo $INFRANODE00PUBLICIP
echo "Create your DNS manually and point to the right IPs when that is done and dns is refreshed set low ttl, continue"
read -n1 -r -p "Press space to continue..." key

fi

if [ $CLUSTER = true ]; then
echo master01.${DNSOPT}
echo $MASTER01PUBLICIP

echo master02.${DNSOPT}
echo $MASTER02PUBLICIP

echo infranode01.${DNSOPT}
echo $INFRA01PUBLICIP

echo loadbalancer.${DNSOPT}
echo $LOAD00PUBLICIP
echo "Create your DNS manually and point to the right IPs when that is done and dns is refreshed set low ttl, continue"
read -n1 -r -p "Press space to continue..." key
fi

if [ $CLUSTER = true ] ; then 
chmod 755 $DIR/ansible-hosts-cluster.sh
sh $DIR/ansible-hosts-cluster.sh
else

chmod 775 $DIR/ansible-hosts-standalone.sh
sh $DIR/ansible-hosts-standalone.sh
fi 
#Adding nfs disks
#tar cvf - nfs.setup.sh | ssh -i ~/.ssh/${KEYNAME}.pem -l ec2-user $NFS00PUBLICIP tar xvf -
scp -i ~/.ssh/${KEYNAME}.pem $DIR/nfs.setup.sh ec2-user@$NFS00PUBLICIP:
ssh -ti ~/.ssh/${KEYNAME}.pem -l ec2-user $NFS00PUBLICIP "sudo bash /home/ec2-user/nfs.setup.sh"
scp -i ~/.ssh/${KEYNAME}.pem ~/.ssh/${KEYNAME}.pem ec2-user@$LAB00PUBLICIP:/home/ec2-user/.ssh/

cat << EOF > $DIR/config
Host *
        IdentityFile ~/.ssh/${KEYNAME}.pem
  GSSAPIAuthentication no
        User ec2-user
EOF
scp -i ~/.ssh/${KEYNAME}.pem $DIR/ansible-hosts  ec2-user@$LAB00PUBLICIP:
scp -i ~/.ssh/${KEYNAME}.pem $DIR/config  ec2-user@$LAB00PUBLICIP:/home/ec2-user/.ssh/
ssh -ti  ~/.ssh/${KEYNAME}.pem -l ec2-user $LAB00PUBLICIP 'chmod 600 .ssh/config'

ssh -ti  ~/.ssh/${KEYNAME}.pem -l ec2-user $LAB00PUBLICIP 'sudo yum -y install atomic-openshift-utils'

ssh -ti  ~/.ssh/${KEYNAME}.pem -l ec2-user $LAB00PUBLICIP 'echo StrictHostKeyChecking no | sudo tee -a /etc/ssh/ssh_config'
ssh -ti  ~/.ssh/${KEYNAME}.pem -l ec2-user $LAB00PUBLICIP 'sudo cp /home/ec2-user/ansible-hosts /etc/ansible/hosts'
ssh -ti  ~/.ssh/${KEYNAME}.pem -l ec2-user $LAB00PUBLICIP 'sudo cp /home/ec2-user/.ssh/* /root/.ssh/'
ssh -ti  ~/.ssh/${KEYNAME}.pem -l ec2-user $LAB00PUBLICIP 'sudo chmod 600 /root/.ssh/config '
echo "Installing Your Environment"
ssh -ti  ~/.ssh/${KEYNAME}.pem -l ec2-user $LAB00PUBLICIP 'sudo ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/byo/config.yml'


#Router and Registry deployment
echo "Deploying router and registry"

ssh -ti ~/.ssh/${KEYNAME}.pem -l ec2-user $MASTER00PUBLICIP "sudo oc get namespace default -o yaml > namespace.default.yaml ; sed -i  '/annotations/ a \ \ \ \ openshift.io/node-selector: region=infra' namespace.default.yaml ; oc replace -f namespace.default.yaml"
ssh -ti ~/.ssh/${KEYNAME}.pem -l ec2-user $MASTER00PUBLICIP "sudo oadm registry --replicas=1 --create --credentials=/etc/origin/master/openshift-registry.kubeconfig --images='registry.access.redhat.com/openshift3/ose-docker-registry:latest'"
#ssh -ti ~/.ssh/${KEYNAME}.pem -l ec2-user $MASTER00PUBLICIP "sudo oadm router router --replicas=1 -service-account=router --stats-password='awslab' --images='registry.access.redhat.com/openshift3/ose-haproxy-router:latest'"

cat << EOF > $DIR/pvconfig
{
  "apiVersion": "v1",
  "kind": "PersistentVolume",
  "metadata": {
    "name": "registry-vol"
  },
  "spec": {
    "capacity": {
        "storage": "5Gi"
        },
    "accessModes": [ "ReadWriteMany" ],
    "nfs": {
        "path": "/nfsexport/registry-volume",
        "server": "$NFS00PRIVATEIP"
    }
  }
}

EOF
cat << EOF > $DIR/pvclaim
{
  "apiVersion": "v1",
  "kind": "PersistentVolumeClaim",
  "metadata": {
    "name": "registry-claim"
  },
  "spec": {
    "accessModes": [ "ReadWriteMany" ],
    "resources": {
      "requests": {
        "storage": "5Gi"
      }
    }
  }
}
EOF

scp -i ~/.ssh/${KEYNAME}.pem $DIR/pvclaim  ec2-user@$MASTER00PUBLICIP:
scp -i ~/.ssh/${KEYNAME}.pem $DIR/pvconfig  ec2-user@$MASTER00PUBLICIP:
ssh -ti ~/.ssh/${KEYNAME}.pem -l ec2-user $MASTER00PUBLICIP "sudo cat pvconfig | oc create -f -"
ssh -ti ~/.ssh/${KEYNAME}.pem -l ec2-user $MASTER00PUBLICIP "sudo cat pvclaim | oc create -f -"

ssh -ti ~/.ssh/${KEYNAME}.pem -l ec2-user $MASTER00PUBLICIP "sudo oc volume dc/docker-registry --add --overwrite -t persistentVolumeClaim --claim-name=registry-claim --name=registry-storage"

for node in  ${MASTER00PUBLICIP}
do
ssh -ti ~/.ssh/${KEYNAME}.pem ec2-user@${node} "
sudo yum -y install httpd-tools
sudo touch /etc/origin/openshift-passwd
sudo htpasswd -b /etc/origin/openshift-passwd testuser flaf42mn
";
done

ssh -ti ~/.ssh/${KEYNAME}.pem -l ec2-user $MASTER00PUBLICIP "sudo oc get namespace openshift-infra -o yaml > openshift-infra.yaml ; sed -i  '/annotations/ a \ \ \ \ openshift.io/node-selector: region=infra' openshift-infra.yaml ; oc replace -f openshift-infra.yaml"
echo creating logging and metrics

cat << EOF > $DIR/sa.json
apiVersion: v1
kind: ServiceAccount
metadata:
  name: metrics-deployer
secrets:
- name: metrics-deployer
EOF

scp -i ~/.ssh/${KEYNAME}.pem sa.json  ec2-user@$MASTER00PUBLICIP: 

ssh -ti ~/.ssh/${KEYNAME}.pem -l ec2-user $MASTER00PUBLICIP "sudo oc project openshift-infra ; sudo cat /home/ec2-user/sa.json | oc create -f -" 
ssh -ti ~/.ssh/${KEYNAME}.pem -l ec2-user $MASTER00PUBLICIP "sudo oc project openshift-infra ; sudo oadm policy add-role-to-user edit system:serviceaccount:openshift-infra:metrics-deployer"
ssh -ti ~/.ssh/${KEYNAME}.pem -l ec2-user $MASTER00PUBLICIP "sudo oadm policy add-cluster-role-to-user cluster-reader system:serviceaccount:openshift-infra:heapster ; sudo  oc secrets new metrics-deployer nothing=/dev/null"

cat << EOF > $DIR/metrics-vol
{
  "apiVersion": "v1",
  "kind": "PersistentVolume",
  "metadata": {
    "name": "cassandra-volume"
  },
  "spec": {
    "capacity": {
        "storage": "15Gi"
        },
    "accessModes": [ "ReadWriteOnce","ReadWriteMany" ],
    "nfs": {
        "path": "/nfsexport/cassandra-volume",
        "server": "$NFS00PRIVATEIP"
    }
  }
}
EOF

cat << EOF > $DIR/logging-sa
apiVersion: v1
kind: ServiceAccount
metadata:
  name: logging-deployer
secrets:
- name: logging-deployer
EOF



scp -i ~/.ssh/${KEYNAME}.pem $DIR/metrics-vol  ec2-user@$MASTER00PUBLICIP:
scp -i ~/.ssh/${KEYNAME}.pem $DIR/logging-sa ec2-user@$MASTER00PUBLICIP:
ssh -ti ~/.ssh/${KEYNAME}.pem -l ec2-user $MASTER00PUBLICIP "sudo oc project openshift-infra ; sudo cat metrics-vol | oc create -f -"
ssh -ti ~/.ssh/${KEYNAME}.pem -l ec2-user $MASTER00PUBLICIP "sudo oc project openshift-infra ; sudo oc process -f metrics-deployer.yaml -v HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.${DNSOPT},CASSANDRA_PV_SIZE=10Gi |  oc create -f -"
ssh -ti ~/.ssh/${KEYNAME}.pem -l ec2-user $MASTER00PUBLICIP "sudo oadm new-project logging --node-selector region=infra ; sudo oc project logging ;  sudo oc secrets new logging-deployer nothing=/dev/null ; sudo cat logging-sa | oc create -f - ; sudo oc policy add-role-to-user edit system:serviceaccount:logging:logging-deployer ; sudo oadm policy add-scc-to-user privileged system:serviceaccount:logging:aggregated-logging-fluentd ; sudo oadm policy add-cluster-role-to-user cluster-reader system:serviceaccount:logging:aggregated-logging-fluentd ; sudo oc process logging-deployer-template -n openshift -v KIBANA_HOSTNAME=kibana.${DNSOPT} -v ES_CLUSTER_SIZE=1 -v ES_INSTANCE_RAM=1024M -v PUBLIC_MASTER_URL=https://master00.${DNSOPT}:8443 -v ENABLE_OPS_CLUSTER=false -v IMAGE_VERSION=latest,IMAGE_PREFIX=registry.access.redhat.com/openshift3/ | oc create -f - ; sudo oc get dc `oc get dc | grep logging-es | awk '{print $1}'` -o json | sed '/containers/i "nodeSelector": { "env": "dev" },' | oc replace -f -"


