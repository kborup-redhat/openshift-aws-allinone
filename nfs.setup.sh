yum install rpcbind nfs-utils -y
systemctl start rpcbind
systemctl start nfs-server
systemctl enable rpcbind
systemctl enable nfs-server
systemctl enable nfs-idmap
systemctl enable nfs-lock.service

grep -q fs.nlm /etc/sysctl.conf
if [ $? -eq 1 ]
then
  sed -i -e '$afs.nfs.nlm_tcpport=53248' -e '$afs.nfs.nlm_udpport=53248' /etc/sysctl.conf
fi
sed -i -e 's/^RPCMOUNTDOPTS.*/RPCMOUNTDOPTS="-p 20048"/' -e 's/^STATDARG.*/STATDARG="-p 50825"/' /etc/sysconfig/nfs
setsebool -P virt_use_nfs=true
mkdir /nfsexport
parted -s /dev/xvdb mklabel msdos
parted -s /dev/xvdb mkpart primary xfs 0 100%
mkfs.xfs /dev/xvdb1
mount /dev/xvdb1 /nfsexport
echo "/dev/xvdb1 /nfsexport xfs defaults 0 0" >>/etc/fstab
echo "Creating mounts for Casandra and Hawkular"
mkdir /nfsexport/{cassandra-volume,reigstry-volume}
chmod -R 777 /nfsexport/*
chown -R nfsnobody:nfsnobody /nfsexport

exportfs -a 

