# How to Use Open Virtual Networking With Mesos

This document describes how to use Open Virtual Networking with Mesos
1.4.0 or later.  This document assumes that you have installed Open
vSwitch by following [INSTALL.rst] or by using the distribution packages
such as .deb or.rpm.  This repo provides a quick start guide at
[INSTALL.UBUNTU.md]

### System Initialization

OVN in "overlay" mode needs a minimum Open vSwitch version of 2.7.

* Start the central components.

OVN architecture has a central component which stores your networking intent
in a database.  Start this central component on the node where you intend to
start your mesos master and which has an IP address of $CENTRAL_IP.

Start ovn-northd daemon.  This daemon translates networking intent from mesos
stored in the OVN_Northbound database to logical flows in OVN_Southbound
database.

```
/usr/share/openvswitch/scripts/ovn-ctl start_northd
```

Run the following commands to open up TCP ports to access the OVN databases.

```
ovn-nbctl set-connection ptcp:6641
ovn-sbctl set-connection ptcp:6642
```

If you want to use SSL instead of TCP for OVN databases, please read
[INSTALL.SSL.md].

### One time setup.

On each host, you will need to run the following command once.  (You need to
run it again if your OVS database gets cleared.  It is harmless to run it
again in any case.)

$LOCAL_IP in the below command is the IP address via which other hosts can
reach this host.  This acts as your local tunnel endpoint.

$ENCAP_TYPE is the type of tunnel that you would like to use for overlay
networking.  The options are "geneve" or "stt".  (Please note that your kernel
should have support for your chosen $ENCAP_TYPE.  Both geneve and stt are part
of the Open vSwitch kernel module that is compiled from this repo.  If you use
the Open vSwitch kernel module from upstream Linux, you will need a minumum
kernel version of 3.18 for geneve.  There is no stt support in upstream Linux.
You can verify whether you have the support in your kernel by doing a `lsmod |
grep $ENCAP_TYPE`.)

```
ovs-vsctl set Open_vSwitch . external_ids:ovn-remote="tcp:$CENTRAL_IP:6642" \
  external_ids:ovn-nb="tcp:$CENTRAL_IP:6641" \
  external_ids:ovn-encap-ip=$LOCAL_IP \
  external_ids:ovn-encap-type="$ENCAP_TYPE"
```

In addition, each Open vSwitch instance in an OVN deployment needs a unique,
persistent identifier, called the "system-id".  If you install OVS from
distribution packaging for Open vSwitch (e.g. .deb or .rpm packages), or if
you use the ovs-ctl utility included with Open vSwitch or the startup
scripts that come with Open vSwitch, it automatically configures a system-id.
If you start Open vSwitch manually, you should set one up yourself.

For example:

```
id_file=/etc/openvswitch/system-id.conf
test -e $id_file || uuidgen > $id_file
ovs-vsctl set Open_vSwitch . external_ids:system-id=$(cat $id_file)
```

And finally, start the ovn-controller.  (You need to run the below command on
every boot)

```
/usr/share/openvswitch/scripts/ovn-ctl start_controller
```

### Node initialization

One each node where you plan to run your mesos agents, clone this repo and
install the CNI plugins.

```
git clone https://github.com/shettyg/ovn-mesos
cd ovn-mesos
pip install -r requirements.txt
sh install.sh
```

### Setting up OVN networks

For each tenant $TENANT, create a OVN router by running the following
command

```
ovn-mesos-init tenant-init --tenant-name $TENANT
```

For the tenant, you need to create a "gateway router" for north-south
connectivity.  You should also decide on a large private subnet
$CLUSTER_IP_SUBNET for the tenant (which can further be divided into smaller
pieces for each network for that tenant).  Consider a host (where you have
installed OVN), with an additional network interface (i.e a physical network
interface in addition to the one you use for mgmt) named "eth1" with an IP
address of $PHYSICAL_IP and a external gateway of $EXTERNAL_GATEWAY, run the
following command.

```
ovn-mesos-init gateway-init --cluster-ip-subnet=$CLUSTER_IP_SUBNET \
    --physical-interface=eth1 --physical-ip=$PHYSICAL_IP \
    --default-gw=$EXTERNAL_GATEWAY --tenant-name="$TENANT"
```

An example is:

```
ovn-mesos-init gateway-init --cluster-ip-subnet="192.168.0.0/16" \
    --physical-interface=eth1 --physical-ip=10.33.75.150/22 \
    --default-gw=10.33.75.253 --tenant-name="coke"
```

Note1: For each tenant, you will need a separate gateway router.  You need this
to support overlapping IP addresses. You can have multiple gateway routers
in the same machine.  But each gateway router needs a separate IP address.
So, if you have a single physical interface "eth1", but it has multiple
IP addresses (aka floating ips), you can still use the same physical interface
for all your gateway routers.  When you create your gateway router, you just
provide a different IP address. You can also have multiple physical interfaces
and you can dedicate each physical interface for a separate tenant's gateway
router.  You can also have multiple machines, each with a subset of
gateway routers.

Note2: You can assign multiple IP addresses to the same gateway router.
This is useful to provide public IPs for some special public facing
containers of a tenant. But you don't need to provide those additional
IP addresses to the "gateway-init" script.  You can use the "DNAT"
table of OVN, to assign them manually.

Note3: OVN also allows a tenant to have multiple gateway routers spread
across multiple machines, but the script "gateway-init" is not coded up for
that scenario.  An advanced user will have to read 'man ovn-nb' to create this
configuration and write his own script.

Note4: It is not necessary to have a single large subnet (as provided by
--cluster-ip-subnet) for all the networks in a tenant. But the "gateway-init"
script is not written to handle disparate networks. An advanced user can
easily create such scenarios, once he is familiar with OVN.  OVN  allows
you to create routers and then have any type of "routes" added to it.

For the above tenant, if your goal is to create a container on network
$SWITCH with a subnet $SUBNET, you should first create that network.
You only need to do this once.  Run the following command on master node.

```
ovn-mesos-init network-init --network-name="$SWITCH" \
    --subnet="$SUBNET" --tenant-name="$TENANT"
```

An example is:

```
ovn-mesos-init network-init --network-name="coke1" \
    --subnet="192.168.1.0/24" --tenant-name="coke"
```

### Passing the network to mesos.

You can pass the required network information to mesos by setting the correct
labels for a network named "ovn".

```
"network_infos" : [{
                     "name": "ovn",
                     "labels": {
                          "labels" : [
                              { "key" : "logical_switch", "value" : "$SWITCH" }
                           ]
                      }
                  }]
```

When the container is created in mesos, the mesos agent will call the
OVN CNI plugin. The OVN CNI plugin inturn will create a logical switch
port in the provided logical_switch.  It uses the passed container_id to
name the logical_port.

## Vagrant

The repo comes with a simple vagrant to try out a basic installation.

[INSTALL.rst]: http://docs.openvswitch.org/en/latest/intro/install
[INSTALL.UBUNTU.md]: docs/INSTALL.UBUNTU.md
[INSTALL.SSL.md]: docs/INSTALL.SSL.md
