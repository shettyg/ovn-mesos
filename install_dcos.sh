#!/bin/sh

mkdir -p /opt/mesosphere/etc/dcos/network/cni/
mkdir -p /opt/mesosphere/active/cni

cp bin/ovn-mesos-plugin /opt/mesosphere/active/cni
cp config/10-ovn.conf /opt/mesosphere/etc/dcos/network/cni/
cp bin/ovn-mesos-init /usr/sbin/ovn-mesos-init
