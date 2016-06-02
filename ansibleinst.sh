SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

source $DIR/vars.sh
cat << EOF > ansible-hosts
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

osm_cluster_network_cidr=10.10.0.0/16
openshift_dns_ip=172.172.0.1
openshift_portal_net = "172.172.0.0/16"
openshift_use_dnsmasq=false
osm_use_cockpit=false


# default subdomain to use for exposed routes
openshift_master_default_subdomain=$DNSOPT

# default project node selector
osm_default_node_selector='env=dev'

# Router selector (optional)
# Router will only be created if nodes matching this label are present.
# Default value: 'region=infra'
#openshift_hosted_router_selector='region=infra'
openshift_hosted_router_selector='region=infra'
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
openshift_registry_selector='region=infra'

# Configure metricsPublicURL in the master config for cluster metrics
openshift_master_metrics_public_url=https://hawkular-metrics.$DNSOPT

# Configure loggingPublicURL in the master config for aggregate logging
openshift_master_logging_public_url=https://kibana.$DNSOPT

# host group for masters
[masters]
master00.$DNSOPT
# host group for etcd
[etcd]
master00.$DNSOPT

# host group for nodes, includes region info
[nodes]
master00.$DNSOPT openshift_public_hostname="master00.$DNSOPT" " openshift_schedulable=False openshift_node_labels="{'name': 'master00'}"
infranode00.$DNSOPT  openshift_public_hostname="infranode00.$DNSOPT" " openshift_node_labels="{'name': 'infranode00','region': '$AWSREGION', 'zone': '$AZ1', 'region': 'infra'}"
node00.$DNSOPT  openshift_node_labels="{'name': 'node00','region': '$AWSREGION', 'zone': '$AZ1', 'env': 'dev'}"
node01.$DNSOPT  openshift_node_labels="{'name': 'node01','region': '$AWSREGION', 'zone': '$AZ1', 'env': 'dev'}"

EOF
