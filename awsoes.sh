#!/bin/bash

script_name=$(basename "$0")
usage ()
{
cat << EOF
usage $script_name OPTIONS

Create an AWS environment running openshift 3.2 under RHEL 7.2

EXAMPLE:
$script_name --rhuser <username> --rhpool <poolid> --cluster <true / false> --lpc <true / false> --awsrhid <rhelImageId> --awsregion <Aws region> --dnsopt=dnsname
OPTIONS EXPLAINED: 
rhuser = your redhat user it
rhpass = your redhat password 
rhpool = from from "subscription-manager list --avalibale --all" (take the repo with openshift in it)
cluster = do you want a clustered AWS setup with loadbalancer, multiple infranodes and routes then this is the option for you (currently under construction)
lpc = Do you want to have a mgmt server where all commands can be run from, then this is the option for you otherwise i will run it all from you local computer.
awsrhid = this is the ID from your AWS console LAUNCH Instance you can pick Red Hat Enterprise Linux 7.2 (HVM), SSD Volume Type - ami-775e4f16 (take the ami- number and insert here)
awsregion = use one of the regions listed in amazon. aws ec2 describe-regions will list something like: 
dnsopt = dnsname of router and servers could be cloud.pfy.dk cloud.redhat.com or cloud.google.com depending on what you own.

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


OPTIONS=`getopt -o h -l help -l rhuser: -l rhpool: -l cluster: -l clusterid: -l lpc: -l awsrhid: -l awsregion: -l dnsopt: -- "$@"`

if [ $? != 0 ]; then
        usage
fi

RHUSER=""
RHPASS=""
RHPOOL=""
CLUSTER=""
CLUSTERID=""
LPC=""
AWSRHID=""
AWSREGION=""
DNSOPT=""

eval set -- "$OPTIONS"

while true; do
case "$1" in
        -h|--help) usage;;
        --rhuser) RHUSER=$2; shift 2;;
        --rhpool) RHPOOL=$2; shift 2;;
	--cluster) CLUSTER=$2; shift 2;;
	--clusterid) CLUSTERID=$2: shift 2;;
	--lpc) LPC=$2; shift 2;;
	--awsrhid) AWSRHID=$2; shift 2;;
	--awsregion) AWSREGION=$2; shift 2;;
	--dnsopt) DNSOPT=$2; shift 2;;
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

echo "Please enter you password for RHN";
stty -echo
read RHN;
stty echo

if [ -z "$RHN" ]; then
        usage
fi

if [ -z "$RHPOOL" ]; then 
	usage
fi

if [ -z "$CLUSTER" ]; then
	usage
fi

if [ -z "$CLUSTERID" ]; then
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
echo "Creating Gateway"
INTERNETGWID=`aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text`
aws ec2 create-tags --resource $INTERNETGWID --tags Key=deployment,Value=paas Key=type,Value=gateway Key=Name,Value=${CLUSTERID}_DMZSubnet
aws ec2 attach-internet-gateway --internet-gateway-id $INTERNETGWID --vpc-id $VPCID

echo "Setting Region IDS"
REGIONIDS=`aws ec2 describe-availability-zones --region ${REGION}  --output json | grep ZoneName | xargs`
AZ1=$REGIONIDS | awk '{print $2}'
AZ2=$REGIONIDS | awk '{print $4}'
AZ3=$REGIONIDS | awk '{print $6}'

DMZSUBNETID=`aws ec2 create-subnet --vpc-id $VPCID --cidr-block 192.168.0.0/26  --availability-zone ${AZ1} --query 'Subnet.SubnetId' --output text`
aws ec2 create-tags --resource $DMZSUBNETID --tags Key=deployment,Value=paas Key=type,Value=subnet Key=Name,Value=${CLUSTERID}_DMZSubnet
INTERNALSUBNETID=`aws ec2 create-subnet --vpc-id $VPCID --cidr-block 192.168.0.128/26 --availability-zone ${AZ1} --query 'Subnet.SubnetId' --output text`
aws ec2 create-tags --resource $INTERNALSUBNETID --tags Key=deployment,Value=paas Key=type,Value=subnet Key=Name,Value=${CLUSTERID}_INTERNALSubnet
EXTERNALROUTETABLEID=`aws ec2 create-route-table --vpc-id $VPCID --query 'RouteTable.RouteTableId' --output text`
aws ec2 create-route --route-table-id $EXTERNALROUTETABLEID --destination-cidr-block 0.0.0.0/0 --gateway-id $INTERNETGWID
aws ec2 associate-route-table --route-table-id $EXTERNALROUTETABLEID --subnet-id $DMZSUBNETID
aws ec2 associate-route-table --route-table-id $EXTERNALROUTETABLEID --subnet-id $INTERNALSUBNETID
#Service groups are hardcoded should we change that ?
MASGNAME=mastersg
INSGNAME=infrasg
NSGNAME=nodesg
NFSNAME=nfssg

MASTERSGID=`aws ec2 create-security-group --group-name $MASGNAME --description "Masters Security Group" --vpc-id $VPCID --query 'GroupId' --output text`
aws ec2 create-tags --resource $MASTERSGID --tags Key=deployment,Value=pass Key=type,Value=SecGroup Key=Name,Value=${CLUSTERID}_${MASGNAME}
INFRASGID=`aws ec2 create-security-group --group-name $INSGNAME --description "Infra Nodes Security Group" --vpc-id $VPCID --query 'GroupId' --output text`
aws ec2 create-tags --resource $INFRASGID --tags Key=deployment,Value=paas Key=type,Value=SecGroup Key=Name,Value=${CLUSTERID}_${INSGNAME}
NODESGID=`aws ec2 create-security-group --group-name $NSGNAME --description "Compute Nodes Security Group" --vpc-id $VPCID --query 'GroupId' --output text`
aws ec2 create-tags --resource $NODESGID --tags Key=deployment,Value=paas Key=type,Value=SecGroup Key=Name,Value=${CLUSTERID}_${NSSGNAME}
NFSSGID=`aws ec2 create-security-group --group-name $NFSNAME --description "NFS Security Group" --vpc-id $VPCID --query 'GroupId' --output text`
aws ec2 create-tags --resource $NFSSGID --tags Key=deployment,Value=paas Key=type,Value=SecGroup Key=Name,Value=${CLUSTERID}_${NFSNAME}


echo "Creating firewalls as per version 3.1 will be updated before final release"

aws ec2 authorize-security-group-ingress --group-id $MASTERSGID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $MASTERSGID --protocol tcp --port 8443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $MASTERSGID --protocol udp --port 4789 --source-group $NODESGID
aws ec2 authorize-security-group-ingress --group-id $MASTERSGID --protocol tcp --port 53 --source-group $NODESGID
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


echo "Setting AWS RedHat Image Name"
AMDID=$AWSRHID

echo "Creating Master Node"

MASTER00OID=`aws ec2 run-instances --image-id $AMIID  --count 1 --instance-type t2.small --key-name ${KEYNAME} --security-group-ids $MASTERSGID --subnet-id $DMZSUBNETID --associate-public-ip-address --query Instances[*].InstanceId --output text`
aws ec2 create-tags --resource $MASTER00ID --tags Key=deployment,Value=paas Key=type,Value=instance Key=Name,Value=${CLUSTERID}_master00 Key=clusterid,Value=${CLUSTERID}
MASTER00PUBLICDNS=`aws ec2 describe-instances --instance-ids $MASTER00ID --query Reservations[*].Instances[*].[PublicDnsName] --output text`
SHORTMASTER00PUBLICDNS=master00.${DNSOPT}
MASTER00PUBLICIP=`aws ec2 describe-instances --instance-ids $MASTER00ID --query Reservations[*].Instances[*].[PublicIpAddress] --output text`
MASTER00PRIVATEIP=`aws ec2 describe-instances --instance-ids $MASTER00ID --query Reservations[*].Instances[*].[PrivateIpAddress] --output text`

if [ $LPC == true ]; then
echo "Creating MGMT Node"
LAB00ID=`aws ec2 run-instances --image-id $AMIID  --count 1 --instance-type t2.small --key-name ${KEYNAME} --security-group-ids $MASTERSGID --subnet-id $DMZSUBNETID --associate-public-ip-address --query Instances[*].InstanceId --output text`
LAB00PUBLICDNS=`aws ec2 describe-instances --instance-ids $LAB00ID --query Reservations[*].Instances[*].[PublicDnsName] --output text`
SHORTLAB00PUBLICDNS=lab.${DNSOPT}
LAB00PUBLICIP=`aws ec2 describe-instances --instance-ids $LAB00ID --query Reservations[*].Instances[*].[PublicIpAddress] --output text`
LAB00PRIVATEIP=`aws ec2 describe-instances --instance-ids $LAB00ID --query Reservations[*].Instances[*].[PrivateIpAddress] --output text`
echo "sleeping while we wait for node to become ready its in the cloud!!"

while test $? -gt 0
   do
   sleep 5 # highly recommended - if it's in your local network, it can try an awful lot pretty quick...
   echo "Trying until it works..."
ssh -ti ~/.ssh/${KEYNAME}.pem ec2-user@${LAB00PUBLICIP} "
sudo sudo rm  /etc/yum.repos.d/*
sudo subscription-manager register --username=${RHNID} --password=${RHNPASS}
sudo subscription-manager attach --pool=${RHNPOOL}
sudo subscription-manager repos --disable='*'
sudo subscription-manager repos --enable="rhel-7-server-rpms" --enable="rhel-7-server-extras-rpms" --enable="rhel-7-server-ose-3.2-rpms"
sudo yum update -y
" ; 
done

fi

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

echo "Creating Infra Node"
INFRANODE00ID=`aws ec2 run-instances --image-id $AMIID  --count 1 --instance-type t2.small --key-name ${KEYNAME} --security-group-ids $INFRASGID $NODESGID --subnet-id $DMZSUBNETID --associate-public-ip-address --query Instances[*].InstanceId --output text`
aws ec2 create-tags --resource $INFRANODE00ID --tags Key=deployment,Value=paas Key=type,Value=instance Key=Name,Value=${CLUSTERID}_infranode00 Key=clusterid,Value=${CLUSTERID}

INFRANODE00PUBLICDNS=`aws ec2 describe-instances --instance-ids $INFRANODE00ID --query Reservations[*].Instances[*].[PublicDnsName] --output text`
SHORTINFRANODE00PUBLICDNS=infranode00.${DNSOPT}
INFRANODE00PRIVATEIP=`aws ec2 describe-instances --instance-ids $INFRANODE00ID --query Reservations[*].Instances[*].[PrivateIpAddress] --output text`
INFRANODE00PUBLICIP=`aws ec2 describe-instances --instance-ids $INFRANODE00ID --query Reservations[*].Instances[*].[PublicIpAddress] --output text`

echo "Creating NFS Node and Adding an extra disk"

NFSNODE00ID=`aws ec2 run-instances --image-id $AMIID  --count 1 --instance-type t2.small --key-name ${KEYNAME} --security-group-ids $NFSSGID --subnet-id $DMZSUBNETID --associate-public-ip-address --query Instances[*].InstanceId --output text`
SHORTNFSNODE00DNS=nfs00.${DNSOPT}
NFS00PRIVATEIP=`aws ec2 describe-instances --instance-ids $NFSNODE00ID --query Reservations[*].Instances[*].[PrivateIpAddress] --output text`
NFS00PUBLICIP=`aws ec2 describe-instances --instance-ids $NFSNODE00ID --query Reservations[*].Instances[*].[PublicIpAddress] --output text`
aws ec2 create-tags --resource $NFSNODE00ID --tags Key=deployment,Value=paas Key=type,Value=instance Key=Name,Value=${CLUSTERID}_nfsnode00 Key=clusterid,Value=${CLUSTERID}
NFSVOL=`aws ec2 create-volume --region $AWSREGION --availability-zone $AZ1 --size 20 --volume-type gp2 --iops 30 | awk '{print $7}'`
aws ec2 attach-volume --volume-id $NFSVOL --instance-id $NFSNODE00ID --device /dev/xvdb 

echo "Setting up RHN on nodes"
nodes="${MASTER00PUBLICDNS} ${INFRANODE00PUBLICDNS} ${NODE00PUBLICDNS} ${NODE01PUBLICDNS}"

for node in ${MASTER00PUBLICDNS} ${INFRANODE00PUBLICDNS} ${NODE00PUBLICDNS} ${NODE01PUBLICDNS} ; do ssh -ti ~/.ssh/${KEYNAME}.pem ec2-user@${node} "
echo Configure the Repositories on ${node}
sudo sudo rm  /etc/yum.repos.d/*
sudo subscription-manager register --username=${RHNID} --password=${RHNPASS}
sudo subscription-manager attach --pool=${RHNPOOL}
sudo subscription-manager repos --disable='*'
sudo subscription-manager repos --enable="rhel-7-server-rpms" --enable="rhel-7-server-extras-rpms" --enable="rhel-7-server-ose-3.2-rpms"
sudo yum update -y
reboot
" ; done
echo "sleeping until all nodes are back up"
sleep 5m
ssh -ti ~/.ssh/${KEYNAME}.pem ec2-user@${MASTER00PUBLICIP} "sudo yum -y install wget git net-tools bind-utils iptables-services bridge-utils bash-completion"

echo "Installing docker"
for node in  ${MASTER00PUBLICDNS} ${INFRANODE00PUBLICDNS} ${NODE00PUBLICDNS} ${NODE01PUBLICDNS} ; do ssh -ti ~/.ssh/${KEYNAME}.pem ec2-user@${node} "
echo Installing Docker on ${node}
sudo yum install docker -y
sudo cp /etc/sysconfig/docker /etc/sysconfig/docker.original
sudo sed -i 's/--selinux-enabled/--selinux-enabled --insecure-registry 172.30.0.0\/0/' /etc/sysconfig/docker " ;
done

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
echo "Creating var file"
set | egrep 'KEYNAME|VPCID|CLUSTERID|INTERNETGWID|REGION|AZ|DMZSUBNETID|INTERNALSUBNETID|EXTERNALROUTETABLEID|MASTERSGID|INFRASGID|NODESGID|AMIID|MASTER0|NODE0|INFRANODE0|RHN|LAB0|DNSOPT' | sort > $DIR/vars.sh
chmod 700 $DIR/vars.sh

chmod 700 $DIR/ansibleinst.sh
./$DIR/ansibleinst.sh

#Adding nfs disks
tar cvf - nfs.setup.sh | ssh -i ~/.ssh/${KEYNAME}.pem -l ec2-user $NFSPUBLICIP tar xvf -
ssh -ti ~/.ssh/${KEYNAME}.pem $NFSPUBLICIP "sudo bash /home/ec2-user/nfs.setup.sh"

if [ $LPC == true ]; then
cd ~/.ssh/
tar cvf - ${KEYNAME}.pem | ssh -i  ~/.ssh/${KEYNAME}.pem -l ec2-user $LAB00PUBLICIP tar xvf - -C .ssh/

cat << EOF > ~/config
Host *
        IdentityFile ~/.ssh/${KEYNAME}.pem
  GSSAPIAuthentication no
        User ec2-user
EOF

cat $DIR/ansible-hosts | ssh -i  ~/.ssh/${KEYNAME}.pem -l ec2-user $LAB00PUBLICIP 'cat > ansible-hosts'
cat ~/config | ssh -i  ~/.ssh/${KEYNAME}.pem -l ec2-user $LAB00PUBLICIP 'cat >> .ssh/config'
ssh -i  ~/.ssh/${KEYNAME}.pem -l ec2-user $LAB00PUBLICIP 'chmod 600 .ssh/config'

ssh -ti  ~/.ssh/${KEYNAME}.pem -l ec2-user $LAB00PUBLICIP 'sudo yum -y install atomic-openshift-utils'

ssh -ti  ~/.ssh/${KEYNAME}.pem -l ec2-user $LAB00PUBLICIP 'echo StrictHostKeyChecking no | sudo tee -a /etc/ssh/ssh_config'
ssh -ti  ~/.ssh/${KEYNAME}.pem -l ec2-user $LAB00PUBLICIP 'sudo cp /home/ec2-user/hosts /etc/ansible/hosts'
ssh -ti  ~/.ssh/${KEYNAME}.pem -l ec2-user $LAB00PUBLICIP 'sudo cp /home/ec2-user/.ssh/* /root/.ssh/'
ssh -ti  ~/.ssh/${KEYNAME}.pem -l ec2-user $LAB00PUBLICIP 'sudo chmod 600 /root/.ssh/config '
echo "Installing Your Environment"
ssh -ti  ~/.ssh/${KEYNAME}.pem -l ec2-user $LAB00PUBLICIP 'sudo ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/byo/config.yml'

else 
echo "Sorry we only do this with a mgmt host at the moment kinda tricked you there dont worry we just made the script ready for the option"
exit 1
fi

for node in  ${MASTER00PUBLICIP}
do
ssh -ti ~/.ssh/${KEYNAME}.pem ec2-user@${node} "
sudo yum -y install httpd-tools
sudo touch /etc/origin/openshift-passwd
sudo htpasswd -b /etc/origin/openshift-passwd testuser flaf42mn
";
done
