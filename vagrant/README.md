## Mesos and OVN

This contains a Vagrant setup for Mesos and OVN integration.  This needs
a minimum vagrant version of 1.8.5 and is known to atleast work on Mac,
Ubuntu 16.04 and Windows 10.

## Howto

From the cloned ovn-mesos repo,
* cd vagrant
* vagrant up 

The above should create 3 VMs named "mesos-master", "mesos-agent1" and
"mesos-agent2".  OVN's central components run on "mesos-master".

### A tenant "Coke"

Log into mesos-master by running
* vagrant ssh mesos-master

Lets create the netwoking needed for a tenant "coke", by running:

```
sudo ovn-mesos-init tenant-init --tenant-name coke
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
sudo ovn-mesos-init gateway-init --cluster-ip-subnet=192.168.0.0/16 \
    --physical-interface=$PHYSICAL_INTERFACE --physical-ip=10.10.1.12/24 \
    --default-gw=10.10.1.1 --tenant-name="coke"
```

Let us now create a network for this tenant with a subnet of "192.168.1.0/24"

```
NETWORK="coke1"
SUBNET="192.168.1.0/24"
sudo ovn-mesos-init network-init --network-name="$NETWORK" \
    --subnet="$SUBNET" --tenant-name="coke"
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

The two containers should be able to talk to each other.

For the two containers, let us go ahead and setup North-South connectivity.

Let us start with creating a L4 load-balancer for the two webservers we
created.

```
sudo ovn-nbctl --may-exist lb-add coke '10.10.1.12:32350' '192.168.1.2:80,192.168.1.3:80'
```

The above command creates a load-balancer. Let us get its $LB_UUID.

```
LB_UUID=`sudo ovn-nbctl --data=bare --no-heading --columns=_uuid find load-balancer name=coke`
```

We now need to assocaite this load-balancer with the gateway router for this
tenant.  To do this, we should get the UUID of the gateway router setup for
this tenant.  When the "ovn-mesos-init gateway-init" script was run for this
tenant, it creates a gateway router with the following name format:
"GR_$TENANT_NAME_$OVS_SYSTEM_ID".  The $OVS_SYSTEM_ID is the unique uuid
for each host that OVS runs on.  Since we ran the "ovn-mesos-init gateway-init"
script on the "mesos-master" host, we can run the following command to get
the $OVS_SYSTEM_ID

```
OVS_SYSTEM_ID=`sudo ovs-vsctl get Open_vSwitch . external_ids:system-id`
```

Since our tenant is "coke", our gateway router's name is
"GR_coke_$OVS_SYSTEM_ID".

Let us assocaite our load-balancer with this gateway router.

```
sudo ovn-nbctl set logical_router GR_coke_$OVS_SYSTEM_ID load_balancer=$LB_UUID
```

From your underlying host, you can now run

```
curl 10.10.1.12:32350
```

Running the above command should randomly give you either "Apache" or an html
page of Nginx.
