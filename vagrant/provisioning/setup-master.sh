#!/bin/bash

# Save trace setting
XTRACE=$(set +o | grep xtrace)
set -o xtrace

# ARGS:
# $1: IP of second interface of master
# $2: IP of third interface of master
# $3: Hostname of the master
# $4: Master switch subnet

PUBLIC_IP1=$1
PUBLIC_IP2=$2

# Find the mgmt IP
INTF=`route -n | grep '^0.0.0.0' | awk '{print $NF}'`
OVERLAY_IP=`ifconfig $INTF | grep 'inet addr' | awk '{print $2}'  | awk -F\: '{print $2}'`

cat > setup_master_args.sh <<EOL
PUBLIC_IP1=$1
PUBLIC_IP2=$2
OVERLAY_IP=$OVERLAY_IP
EOL

# For agents to use to connect to the master.
cat > /vagrant/master_ip.sh <<EOL
export MASTER_IP=$OVERLAY_IP
EOL

# FIXME(mestery): Remove once Vagrant boxes allow apt-get to work again
sudo rm -rf /var/lib/apt/lists/*

# Install OVS
sudo apt-get install apt-transport-https
echo "deb https://packages.wand.net.nz $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/wand.list
sudo curl https://packages.wand.net.nz/keyring.gpg -o /etc/apt/trusted.gpg.d/wand.gpg
sudo apt-get update
sudo apt-get build-dep dkms
sudo apt-get install python-six openssl python-pip -y
sudo -H pip install --upgrade pip

sudo apt-get install openvswitch-datapath-dkms=2.7.0-1 -y
sudo apt-get install openvswitch-switch=2.7.0-1 openvswitch-common=2.7.0-1 -y
sudo -H pip install ovs

sudo ovs-vsctl set Open_vSwitch . external_ids:ovn-remote="tcp:$OVERLAY_IP:6642" \
                                  external_ids:ovn-nb="tcp:$OVERLAY_IP:6641" \
                                  external_ids:ovn-encap-ip=$OVERLAY_IP \
                                  external_ids:ovn-encap-type=geneve

# Install OVN
sudo apt-get install ovn-central=2.7.0-1 ovn-common=2.7.0-1 -y

# Install ovn-mesos
git clone https://github.com/shettyg/ovn-mesos
pushd ovn-mesos
sudo -H pip install -r requirements.txt
sudo sh install.sh
popd

sudo ovn-nbctl set-connection ptcp:6641
sudo ovn-sbctl set-connection ptcp:6642

# Install Mesos
wget http://repos.mesosphere.com/ubuntu/pool/main/m/mesos/mesos_1.3.0-2.0.3.ubuntu1604_amd64.deb
sudo dpkg -i mesos_*.deb
sudo apt-get install -f -y

# Start mesos master
nohup sudo mesos-master --ip=$OVERLAY_IP --work_dir=/var/lib/mesos 2>&1 0<&- &>/dev/null &

# Restore xtrace
$XTRACE
