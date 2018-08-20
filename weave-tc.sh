#!/bin/sh -ex

# DNSMASQ_PORT represents the port your DNS server is listening on.
#
# Note that on Kubernetes, this is the port the DNS process/container uses, and not the
# port that is exposed by the Service.
DNSMASQ_PORT=${DNSMASQ_PORT:-53}

# NET_OVERLAY_IF represents the network interface that your overlay network uses.
NET_OVERLAY_IF=${NET_OVERLAY_IF:-weave}

# Force the kernel to re-create the dummy mq scheduler on the default interface,
# - as the child qdiscs may have been set to pfifo_fast at boot even if the default
# appear to be ‘fq_codel’ (we also set the default to fq_codel regardless, for older
# systems)
# - as the qdiscs are using a quantum based on the boot MTU, which may have changed
# after DHCP has gotten the proper MTU.
#
# Setting mq will only work if the NIC supports multiple TX/RX queues, therefore
# creating and grafting each class/qdiscs to specific CPU cores. In case the NIC
# does not support that, we simply ignore the error.
sysctl -w net.core.default_qdisc=fq_codel
tc qdisc del dev $(route | grep '^default' | grep -o '[^ ]*$') root 2>/dev/null || true
tc qdisc add dev $(route | grep '^default' | grep -o '[^ ]*$') root handle 0: mq || true

# Traffic leaving the $NET_OVERLAY_IF interface onto the default interface will be encapsulated 
# and encrypted in IPSec (ESP), therefore, we may only do traffic shaping work on this
# interface.
#
# The $NET_OVERLAY_IF interface is a virtual interface, which is set to noqueue by default and does
# not support mq nor multiq. Therefore, we go directly to the point and create a a 2-bands
# priomap, that sends all traffic (regardless of the TOS octet) to the 2nd band, a simple 
# fq_codel. We then define the 1st band as a netem with the a small delay, that appears to 
# be avoid the race in a statistically satisfying manner, and that is controlled by a pareto
# distribution (k=4ms, a=1ms) and route traffic marked by 0x100/0x100 to it.
#
# Using iptables, we mark 0x100/0x100 the UDP traffic destined to port $DNSMASQ_PORT, that have
# the DNS query bits set (fast check) and then that contain at least one question with QTYPE=AAAA.
while ! ip link | grep "$NET_OVERLAY_IF" > /dev/null; do sleep 1; done
tc qdisc del dev $NET_OVERLAY_IF root 2>/dev/null || true
tc qdisc add dev $NET_OVERLAY_IF root handle 1: prio bands 2 priomap 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1

tc qdisc add dev $NET_OVERLAY_IF parent 1:2 handle 12: fq_codel

tc qdisc add dev $NET_OVERLAY_IF parent 1:1 handle 11: netem delay 4ms 1ms distribution pareto
tc filter add dev $NET_OVERLAY_IF protocol all parent 1: prio 1 handle 0x100/0x100 fw flowid 1:1
iptables -A POSTROUTING -t mangle -p udp --dport $DNSMASQ_PORT -m string -m u32 --u32 "28 & 0xF8 = 0" --hex-string "|00001C0001|" --algo bm --from 40 -j MARK --set-mark 0x100/0x100

while sleep 3600; do :; done

# Useful testing commands:
#
# iperf3
# - On-Host Server:     docker run -d --rm --net=host --pid=host networkstatic/iperf3 -s -V
# - On-Host Client:     docker run -it --rm --net=host --pid=host networkstatic/iperf3 -c 10.3.6.30 -V -P 16 -i 0
# - On-Host UDP Client: docker run -it --rm --net=host --pid=host networkstatic/iperf3 -c 10.3.6.30 -u -V -P 16 -t 10 -b 10G -i 0
# - iperf3 Client:       docker run -it --rm networkstatic/iperf3 -c 10.3.6.30 -V -P 16 -i 0
# - iperf3  UDP Client:   docker run -it --rm networkstatic/iperf3 -c 10.3.6.30 -u -V -P 16 -t 10 -b 10G -i 0
#
# dnsperf
# - Google.com (A/AAAA): echo -e "google.com A\ngoogle.com AAAA" > google && dnsperf -s 172.17.0.10 -l 30 -c 100 -d google
# - Google.com (AAAA):   echo "google.com AAAA" > google && dnsperf -s 172.17.0.10 -l 30 -c 100 -d google
# - Varied targets:      wget ftp://ftp.nominum.com/pub/nominum/dnsperf/data/queryfile-example-current.gz; gzip -d queryfile-example-current.gz; dnsperf -s 172.17.0.10 -l 11 -c 10 -Q 60 -d queryfile-example-current
#
# parallel cURLs (very keen to trigger the race condition)
# - seq 1000 | parallel -j50 --joblog log curl -s https://google.com/ ">" /dev/null; sort -k4 -n log
#
# monitoring helpers:
# - htop:                                   docker run --rm -it --pid host frapsoft/htop
# - insert_failed (on the DNS server host): docker run --net=host --privileged --rm -it --entrypoint=watch cap10morgan/conntrack -n1 conntrack -S
# - marked packets count:                   iptables -L POSTROUTING -v -n -t mangle --line-numbers | grep 00001c0001
