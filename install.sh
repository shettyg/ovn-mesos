#!/bin/sh

mkdir -p /var/lib/mesos/cni/config
mkdir -p /var/lib/mesos/cni/plugins

cp bin/ovn-mesos-plugin /var/lib/mesos/cni/plugins
cp config/10-ovn.conf /var/lib/mesos/cni/config
