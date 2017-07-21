#!/bin/bash

# Save trace setting
XTRACE=$(set +o | grep xtrace)
set -o xtrace

# ARGS:
# $1: IP of second interface of agent
# $2: IP of third interface of agent

OVERLAY_IP="$1"

# Find the master IP
source /vagrant/master_ip.sh

cat > setup_agent_args.sh <<EOL
OVERLAY_IP=$OVERLAY_IP
MASTER_IP=$MASTER_IP
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

sudo ovs-vsctl set Open_vSwitch . external_ids:ovn-remote="tcp:$MASTER_IP:6642" \
                                  external_ids:ovn-nb="tcp:$MASTER_IP:6641" \
                                  external_ids:ovn-encap-ip=$OVERLAY_IP \
                                  external_ids:ovn-encap-type=geneve


# Install OVN
sudo apt-get install ovn-host=2.7.0-1 ovn-common=2.7.0-1 -y

# Install ovn-mesos
git clone https://github.com/shettyg/ovn-mesos
pushd ovn-mesos
sudo -H pip install -r requirements.txt
sudo sh install.sh
popd

# Install Mesos
wget http://repos.mesosphere.com/ubuntu/pool/main/m/mesos/mesos_1.3.0-2.0.3.ubuntu1604_amd64.deb
sudo dpkg -i mesos_*.deb
sudo apt-get install -f -y

# Start mesos agent
nohup sudo mesos-agent --ip=$OVERLAY_IP --advertise_ip=$OVERLAY_IP --master=$MASTER_IP:5050  --work_dir=/var/lib/mesos --isolation=filesystem/linux,docker/runtime  --image_providers=docker --containerizers=mesos --network_cni_config_dir=/var/lib/mesos/cni/config --network_cni_plugins_dir=/var/lib/mesos/cni/plugins --http_command_executor 1>&2 2>/home/ubuntu/mesos-agent.log &

# Restore xtrace
$XTRACE
