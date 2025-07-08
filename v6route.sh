#!/bin/bash

# Default drop policy
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT

# Allow established/related
ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow SSH
# ip6tables -A INPUT -p tcp --dport 22 -j ACCEPT

# Allow necessary ICMPv6
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -j ACCEPT
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -j ACCEPT
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type packet-too-big -j ACCEPT

# Block ping6
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -j DROP

# Block traceroute6
ip6tables -A OUTPUT -p ipv6-icmp --icmpv6-type time-exceeded -j DROP

# Block port unreachable responses
ip6tables -A OUTPUT -p ipv6-icmp --icmpv6-type destination-unreachable -j DROP
