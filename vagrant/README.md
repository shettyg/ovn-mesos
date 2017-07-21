## Mesos and OVN

This contains a Vagrant setup for Kubernetes and OVN integration.  This needs
a minimum vagrant version of 1.8.5 and is known to atleast work on Mac,
Ubuntu 16.04 and Windows 10.

Howto
----

From the cloned ovn-mesos repo,
* cd vagrant
* vagrant up 

The above should create 3 VMs named "mesos-master", "mesos-agent1" and
"mesos-agent2".  OVN's central components run on "mesos-master".

Log into mesos-master by running
* vagrant ssh mesos-master

Lets create the netwoking needed for a tenant "coke".

```
TENANT=coke
sudo ovn-mesos-init tenant-init --tenant-name $TENANT
```

'mesos-master' node has three physical interfaces. The first
physical interface is exclusively used by vagrant for mgmt.

The second and third interface are used by the ovn-mesos
integration.  The second interface is for mesos-agent to
talk to mesos-master. This interface is also used by
ovn-controller running in mesos-agent to talk to OVN's databases
running in mesos-master.  This interface is also used as the
tunnel endpoint for overlay networks created by OVN.

The third interface is used here for the purpose of gateway.
It's IP address is 10.10.1.12/24.  Get the interface name of this
interface.  Let us assume it is "enp0s9".  For the tenant "coke",
we will use this interface for gateway purposes.

```
PHYSICAL_INTERFACE="enp0s9"
TENANT="coke"
sudo ovn-mesos-init gateway-init --cluster-ip-subnet=192.168.0.0/16 \
    --physical-interface=$PHYSICAL_INTERFACE --physical-ip=10.10.1.12/24 \
    --default-gw=10.10.1.1 --tenant-name="$TENANT"
```

Let us no create a network for this tenant with a subnet of "192.168.1.0/24"

```
TENANT="coke"
NETWORK="coke1"
SUBNET="192.168.1.0/24"
sudo ovn-mesos-init network-init --network-name="$NETWORK" \
    --subnet="$SUBNET" --tenant-name="$TENANT"
```

Let us go ahead and run the first container (a apache webserver) now in
network "coke1"

```
source setup_master_args.sh
sudo mesos-execute --master=$OVERLAY_IP:5050 --task=file:///home/ubuntu/apachecoke
```

This container gets created in one of the agent VMs. You can find it's network
namespace by running 'ip netns ls' on the both agents.  Assuming the network
namespace is $NAMESPACE1, you can get its allocated IP address with:

```
sudo ip netns exec $NAMESPACE1 ifconfig -a
```

Let us go ahead and run the second container (a nginx webserver) now in
network "coke1"

```
source setup_master_args.sh
sudo mesos-execute --master=$OVERLAY_IP:5050 --task=file:///home/ubuntu/nginxcoke
```
