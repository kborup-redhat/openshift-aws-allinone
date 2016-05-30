SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
./$DIR/vars.sh
cat << EOF > $DIR/ansible-hosts
# Create an OSEv3 group that contains the master, nodes, etcd, and lb groups.
[OSEv3:children]
masters
etcd
nodes

# Set variables common for all OSEv3 hosts
[OSEv3:vars]
ansible_ssh_user=ec2-user
ansible_sudo=true
deployment_type=openshift-enterprise
debug_level=4
openshift_master_identity_providers=[{'name': 'htpasswd_auth', 'login': 'true', 'challenge': 'true', 'kind': 'HTPasswdPasswordIdentityProvider', 'filename': '/etc/origin/openshift-passwd'}]
osm_default_node_selector='env=dev'

# Cloud Provider Configuration
#
# Note: You may make use of environment variables rather than store
# sensitive configuration within the ansible inventory.
# For example:
#openshift_cloudprovider_aws_access_key="{{ lookup('env','AWS_ACCESS_KEY_ID') }}"
#openshift_cloudprovider_aws_secret_key="{{ lookup('env','AWS_SECRET_ACCESS_KEY') }}"
#
# AWS
#openshift_cloudprovider_kind=aws
# Note: IAM profiles may be used instead of storing API credentials on disk.
#openshift_cloudprovider_aws_access_key=aws_access_key_id
#openshift_cloudprovider_aws_secret_key=aws_secret_access_key

# default subdomain to use for exposed routes
openshift_master_default_subdomain=${DOMAIN}

# default project node selector
osm_default_node_selector='env=dev'

# Router selector (optional)
# Router will only be created if nodes matching this label are present.
# Default value: 'region=infra'
#openshift_hosted_router_selector='region=infra'
openshift_hosted_router_selector='env=infra'
openshift_hosted_router_replicas=1



# Openshift Registry Options
#
# An OpenShift registry will be created during install if there are
# nodes present with labels matching the default registry selector,
# "region=infra". Set openshift_node_labels per node as needed in
# order to label nodes.

# Registry selector (optional)
# Registry will only be created if nodes matching this label are present.
# Default value: 'region=infra'
openshift_registry_selector='env=infra'

# Configure metricsPublicURL in the master config for cluster metrics
openshift_master_metrics_public_url=https://hawkular-metrics.${DOMAIN}

# Configure loggingPublicURL in the master config for aggregate logging
openshift_master_logging_public_url=https://kibana.${DOMAIN}

# host group for masters
[masters]
master00.${DOMAIN}
# host group for etcd
[etcd]
master00.${DOMAIN}

# host group for nodes, includes region info
[nodes]
master00.${DOMAIN} openshift_public_hostname="master00.${DOMAIN}" openshift_hostname="${MASTER00PRIVATEIP}" openshift_schedulable=False openshift_node_labels="{'name': 'master00'}"
infranode00.${DOMAIN}  openshift_public_hostname="infranode00.${DOMAIN}" openshift_hostname="${INFRANODE00PRIVATEIP}" openshift_node_labels="{'name': 'infranode00','region': 'ap-southeast-2', 'zone': 'ap-southeast-2a', 'env': 'infra'}"
node00.${DOMAIN} openshift_hostname="${NODE00PRIVATEIP}" openshift_node_labels="{'name': 'node00','region': 'ap-southeast-2', 'zone': 'ap-southeast-2a', 'env': 'dev'}"
node01.${DOMAIN}  openshift_hostname="${NODE01PRIVATEIP}" openshift_node_labels="{'name': 'node01','region': 'ap-southeast-2', 'zone': 'ap-southeast-2a', 'env': 'dev'}"

EOF
