#!/bin/bash
sudo sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"

IP="sudo /sbin/ip"
TC="sudo /sbin/tc"
NSCMD="sudo /sbin/ip netns exec"

IMAGE_HOST_VETH=IMAGEDETECTHOST
IMAGE_CONT_VETH=IMAGEDETECTCONT
IMAGE_DETECT_NAMESPACE=imagedetection
IMAGE_DETECT_MOB_HOST_IP_ADDR="150.0.0.2"
IMAGE_DETECT_CONT_IP_ADDR="150.0.0.1"
IMAGE_DETECT_DEST_IP_ADDR="52.53.184.124"


veth_imagedetect_ns=($IMAGE_HOST_VETH 70:11:00:00:00:00 $IMAGE_CONT_VETH 70:00:00:00:00:00)
IMAGE_DETECT_PORT=12345
IMAGE_PROCESSING_PYTHON_SCRIPT="/home/istguser1/image_processor.py"
IMAGE_PROCESSING_SHELL_SCRIPT="/home/istguser1/plate-openalpr/demo/start-server.sh"
IMAGE_PROCESSING_APPLICATION="/home/istguser1/plate-openalpr/demo/server $IMAGE_DETECT_PORT"
KAON_VERIZON_DEMO="/home/istguser1/KaonVerizon/runudpmultiplexer.sh"

MTUSIZE=32768
STARTING_QE_INDEX=1
ENDING_QE_INDEX=10

MOB_IFACE=eno49
MOB_MAC="5c:b9:01:c3:d9:38"
MOB_MAC_OF_NEXT_HOP="e4:d3:f1:b1:b4:83"
MAC_OF_BBI_NEXT_HOP="d8:67:d9:07:76:c1"

LOCAL_HOST="10.2.40.161/32"

MOBILE_TRAFFIC_SRC="10.136.66.230/32"
MOBILE_TRAFFIC_SRC2="10.136.66.233/32"
MOBILE_TRAFFIC_SRC3="10.136.66.232/32"

VETH_SWAP1=VETHSWAP1
VETH_SWAP1_MAC="80:00:00:00:00:00"
VETH_SWAP2=VETHSWAP2
VETH_SWAP2_MAC="90:00:00:00:00:00"

setup_single_paired_veth() {
  host_mob_veth=$1
  host_mob_veth_mac=$2
  ns_mob_veth=$3
  ns_mob_veth_mac=$4
  mtu=$MTUSIZE

  echo "Adding link $host_mob_veth with mac $host_mob_veth_mac type veth with the peer link named as $ns_mob_veth"
  $IP link add $host_mob_veth address $host_mob_veth_mac type veth peer name $ns_mob_veth

  echo "setting $ns_mob_veth mac $ns_mob_veth_mac"
  $IP link set $ns_mob_veth address $ns_mob_veth_mac

  echo "Bring $host_mob_veth link up with mtu $mtu"
  $IP link set $host_mob_veth up mtu $mtu

  echo "Bring $ns_mob_veth link up with mtu $mtu"
  $IP link set $ns_mob_veth up mtu $mtu
}


delete_veth() {
  host_mob_veth=$1
  ns_mob_veth=$2

  echo "Deleting link for $host_mob_veth"
  $IP link del $host_mob_veth

  echo "Deleting link for $ns_mob_veth"
  $IP link del $ns_mob_veth
}

create_ingress_qdiscs() {
  veth=$1
  echo "Creating ingress QDiscs for $veth"
  $TC qdisc add dev $veth ingress
}

create_egress_fq_qdiscs() {
  veth=$1
  echo "Creating egress QDiscs for $veth"
  #$TC qdisc add dev $veth root handle 1: fq
  $TC qdisc add dev $veth root handle 1: fq
}

create_egress_prio_qdiscs() {
  veth=$1
  echo "Creating egress QDiscs for $veth"
  $TC qdisc add dev $veth root handle 1: prio
}

delete_qdiscs() {
  veth=$1
  echo "Deleting ingress QDiscs for $veth"
  $TC qdisc del dev $veth ingress
  echo "Deleting egress QDiscs for $veth"
  #$TC qdisc del dev $veth root handle 1: prio
  $TC qdisc del dev $veth root handle 1: fq
  $TC qdisc del dev $veth root handle 1: prio
}

create_tc_actions_on_image_processing_host_interface() {
  specified_veth=$1
  vm_iface=$2
  server_port=$3
  src_mac=$4
  dst_mac=$5
  ingress_filter='ffff:'
  egress_filter='1:'

  echo "Creating ingress filter for $specified_veth to match protocol TCP SYN-ACK and source port $server_port and send it to $vm_iface so that the packet is sent to the internet."
  $TC filter add dev $specified_veth parent $ingress_filter prio 1 protocol ip u32 \
      match ip protocol 0x6 0xff \
      match u8 0x12 0xff at 33 \
      match ip sport $server_port 0xff \
      action skbedit ptype host \
      action skbmod dmac $dst_mac \
      action skbmod smac $src_mac \
      action mirred egress redirect dev $vm_iface


  echo "Creating ingress filter for $specified_veth to match protocol TCP and source port $server_port and send it to $vm_iface so that the packet is sent to the internet."
  $TC filter add dev $specified_veth parent $ingress_filter prio 2 protocol ip u32 \
      match ip protocol 0x6 0xff \
      match ip sport $server_port 0xff \
      action skbedit ptype host \
      action skbmod dmac $dst_mac \
      action skbmod smac $src_mac \
      action mirred egress redirect dev $vm_iface

}

create_tc_actions_on_imagedetect_container_interface() {
  specified_veth=$1  
  dest_port=$2
  namespace=$3
  application_port=$4

  ingress_filter='ffff:'
  egress_filter='1:'

  echo "Creating ingress QDiscs for ${veth_imagedetect_ns[2]}"
  $IP netns exec $namespace $TC qdisc add dev ${veth_imagedetect_ns[2]} ingress

  echo "Creating egress QDiscs for ${veth_imagedetect_ns[2]}"
  $IP netns exec $namespace $TC qdisc add dev ${veth_imagedetect_ns[2]} root handle 1: fq

  echo "Creating ingress filter for namespace $namespace -> $specified_veth to match protocol TCP and packet is SYN and dest port $dest_port and send it to host."
  $TC -n $namespace filter add dev $specified_veth prio 1 parent $ingress_filter protocol ip u32 \
      match ip protocol 0x6 0xff \
      match u8 0x2 0xff at 33 \
      match ip dport $dest_port 0xff \
      action skbedit ptype host
      #action trproxy lport $application_port mark 0 mask 0 index 1

  echo "Creating ingress filter for namespace $namespace -> $specified_veth to match protocol TCP and packet is ACK and dest port $dest_port and send it to host."
  $TC -n $namespace filter add dev $specified_veth prio 2 parent $ingress_filter protocol ip u32 \
      match ip protocol 0x6 0xff \
      match u8 0x10 0xff at 33 \
      match ip dport $dest_port 0xff \
      action skbedit ptype host
      #action trproxy lport $application_port mark 0 mask 0 index 1

 echo "Creating ingress filter for namespace $namespace -> $specified_veth to match protocol TCP and dest port $dest_port and send it to host."
  $TC -n $namespace filter add dev $specified_veth prio 3 parent $ingress_filter protocol ip u32 \
      match ip protocol 0x6 0xff \
      match ip dport $dest_port 0xff \
      action skbedit ptype host
      #action trproxy lport $application_port mark 0 mask 0 index 1

}

create_tc_actions_on_veth_swap() {
mob_traffic_src=$1
veth_swap=$2
prio=$3

 #echo "Creating Egress filter on $veth_swap to route the regular traffic with src ip $mob_traffic_src egress to the internet with src mac $MOB_MAC and dst mac $MAC_OF_BBI_NEXT_HOP."
  echo "Creating Egress filter on $veth_swap to route the regular traffic with src ip $mob_traffic_src egress to the internet with src mac $MOB_MAC and dst mac $MAC_OF_BBI_NEXT_HOP."
  $TC filter add dev $veth_swap parent 1: prio $prio protocol ip u32 \
  match ip src $mob_traffic_src \
  action skbedit ptype host \
  action skbmod smac $MOB_MAC  \
  action skbmod dmac $MAC_OF_BBI_NEXT_HOP \
  action mirred egress redirect dev $MOB_IFACE

 prio=$((prio+1))

echo "Creating Egress filter on $veth_swap to route the regular traffic with dst ip $mob_traffic_src andegress to mobile with src mac  $MOB_MAC and dst mac $MOB_MAC_OF_NEXT_HOP."
  $TC filter add dev $veth_swap parent 1: prio $prio protocol ip u32 \
  match ip dst $mob_traffic_src \
  action skbedit ptype host \
  action skbmod smac $MOB_MAC  \
  action skbmod dmac $MOB_MAC_OF_NEXT_HOP \
  action mirred egress redirect dev $MOB_IFACE
}

create_tc_actions_on_specified_veth() {
  veth_src=$1
  mob_traffic_dst=$2
  veth_dst=$3
  packet_src_mac=$4
  packet_dst_mac=$5
  dest_port=$6

  ingress='ffff:'
  egress='1:'
  starting_prio=1

 echo "Creating Ingress filter on $veth_src to route the packets with dest ip $mob_traffic_dst and dest port = $dest_port and protocol TCP to the container veth $veth_dst and rewrite src mac as $packet_src_mac and dst mac as $packet_dst_mac."
  $TC filter add dev $veth_src prio $starting_prio parent $ingress protocol ip u32 \
      match ip protocol 0x6 0xff \
      match ip dport $dest_port 0xff \
      action skbmod smac $packet_src_mac \
      action skbmod dmac $packet_dst_mac \
      action skbedit ptype host \
      action mirred egress redirect dev $veth_dst
      #action skbedit mark 1 \
      #action ife encode type 0xfefe allow mark dst ${veth_haproxy_ns[3]}\
      #match ip dst $mob_traffic_dst \
}

route_the_packets_to_host_and_veth_swap() {
  veth_src=$1
  starting_prio=$2
  mob_traffic_src=$3
  veth_dst=$4
  host_local_ip=$5
  ingress='ffff:'

echo "Creating Ingress filter on $veth_src to route the MOBILE packets with source ip $mob_traffic_src, and dest IPv4 address $host_local_ip entering this interface to host and accept it."
  $TC filter add dev $veth_src prio $starting_prio parent $ingress protocol ip u32 \
      match ip src $mob_traffic_src \
      match ip dst $host_local_ip \
      action skbedit ptype host \
      action ok

  starting_prio=$((starting_prio+1))

echo "Creating Ingress filter on $veth_src to route the MOBILE packets with source ip $mob_traffic_src entering this interface to the container veth $veth_dst."
  $TC filter add dev $veth_src prio $starting_prio parent $ingress protocol ip u32 \
      match ip src $mob_traffic_src \
      action skbedit ptype host \
      action mirred egress redirect dev $veth_dst

  starting_prio=$((starting_prio+1))

echo "Creating Ingress filter on $veth_src to route the MOBILE packets with dest ip $mob_traffic_src entering this interface to the container veth $veth_dst."
  $TC filter add dev $veth_src prio $starting_prio parent $ingress protocol ip u32 \
      match ip dst $mob_traffic_src \
      action skbedit ptype host \
      action mirred egress redirect dev $veth_dst

  starting_prio=$((starting_prio+1))
}

create_qe() {
starting_qe_index=$1
ending_qe_index=$2
current_qe_index=$starting_qe_index
while [ $current_qe_index -le $ending_qe_index ]
do
	echo "setting up QE with index $current_qe_index"
	sudo tc -s actions add action qe bucket 10000000  multiplier 0 credit 1000000 exceedact pipe index $current_qe_index
	(( current_qe_index ++ ))
done
}

delete_qe() {
starting_qe_index=$1
ending_qe_index=$2
current_qe_index=$starting_qe_index
while [ $current_qe_index -le $ending_qe_index ]
do
	echo "Deleting QE with index $current_qe_index"
	sudo tc -s actions del action qe index $current_qe_index
	(( current_qe_index ++ ))
done
}

create_police() {
starting_police_index=$1
ending_police_index=$2
current_police_index=$starting_police_index
while [ $current_police_index -le $ending_police_index ]
do
	echo "setting up Police with index $current_police_index"
	sudo tc -s actions add action police rate 1000000  burst 2000000 mtu 1500 peakrate 100000 conform-exceed pipe index $current_police_index
	(( current_police_index ++ ))
done
}

delete_police() {
starting_police_index=$1
ending_police_index=$2
current_police_index=$starting_police_index
while [ $current_police_index -le $ending_police_index ]
do
	echo "Deleting police with index $current_police_index"
	sudo tc -s actions del action police index $current_police_index
	(( current_police_index ++ ))
done
}


setup_single_veth_namespace_container() {
  skbmark=$1
  namespace=$2
  ns_mob_veth=$3
  host_mob_veth=$4
  host_mob_ip=$5
  ns_mob_ip=$6
  mtu=$MTUSIZE

  echo "Creating namespace $namespace"
  $IP netns add $namespace

  echo "Setting device local up in $namespace"
  $IP -n $namespace link set dev lo up

  echo "Setting veth devices $ns_mob_veth to namespace $namespace"
  $IP link set dev $ns_mob_veth netns $namespace

  echo "Bring up links $ns_mob_veth with mtu $mtu in namespace $namespace"
  $IP -n $namespace link set dev $ns_mob_veth mtu $mtu

  echo "Bring up device $ns_mob_veth up in namespace $namespace"
  $IP -n $namespace link set dev $ns_mob_veth up
 
  echo "Echo 0 to /proc/sys/net/ipv4/conf/$ns_mob_veth/rp_filter"
  $IP netns exec $namespace sudo sh -c "echo 0 > /proc/sys/net/ipv4/conf/$ns_mob_veth/rp_filter"

  echo "Echo 0 to /proc/sys/net/ipv4/conf/all/rp_filter"
  $IP netns exec $namespace sudo sh -c "echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter"

  echo "set fwmark_accept=1"
  $IP netns exec $namespace sysctl -w net.ipv4.tcp_fwmark_accept=1

  echo "set fwmark_reflect=1"
  $IP netns exec $namespace sysctl -w net.ipv4.fwmark_reflect=1

  echo "Creating tables."
  $IP -n $namespace rule add iif $ns_mob_veth lookup 100
  $IP -n $namespace -6 rule add iif $ns_mob_veth lookup 100

  # Declare all IPv4 packets locally, i.e. dests are assigned to this host,
  # so packets will be delivered locally
  echo "Declaring all ipv4 packet locally to this host. 0.0.0.0/0 dev lo table 100 in $namespace"
  $IP -n $namespace route add local 0.0.0.0/0 dev lo table 100
  
  echo "Declaring all ipv6 packet locally to this host. 0.0.0.0/0 dev lo table 100 in $namespace"
  $IP -n $namespace -6 route add local ::/0 dev lo table 100 

  echo "Assigning IP address $ns_mob_ip/16 dev $ns_mob_veth"
  $IP -n $namespace addr add $ns_mob_ip/16 dev $ns_mob_veth

  echo "Adding a default route for $host_mob_ip in $namespace"
  $IP -n $namespace route add default via $host_mob_ip

  echo "Assigning IP address $host_mob_ip/16 via dev $host_mob_veth"
  $IP addr add $host_mob_ip/16 dev $host_mob_veth

  echo "echo 0 > /proc/sys/net/ipv4/conf/$host_mob_veth/rp_filter"
  sudo sh -c "echo 0 > /proc/sys/net/ipv4/conf/$host_mob_veth/rp_filter"

  echo "echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter"
  sudo sh -c "echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter"

  #echo "Turn off arp on $ns_mob_veth"
  $IP netns exec $namespace ip link set $ns_mob_veth arp off

  #echo "sudo ip route add 10.1.100.107 via 10.1.1.1 dev MOBWGETHOST"
  #sudo ip route add $MOB_WGET_CONT_IPADDR via 10.1.100.100 dev eth0
  #sudo ip route add $MOB_WGET_CONT_IPADDR via 10.1.100.100 dev MOBWGETHOST

  sudo sh -c "ip link set $host_mob_veth arp off"

}

create_qdiscs() {
  veth=$1
  echo "Creating ingress QDiscs for $veth"
  $TC qdisc add dev $veth ingress
  echo "Creating egress QDiscs for $veth"
  $TC qdisc add dev $veth root handle 1: prio
}

delete_qdiscs() {
  veth=$1
  echo "Deleting ingress QDiscs for $veth"
  $TC qdisc del dev $veth ingress
  echo "Deleting egress QDiscs for $veth"
  $TC qdisc del dev $veth root handle 1: prio
}

create_infrastructure() {

   #echo "inserting kernel modules"
   # Environment Setup
   #sudo insmod /home/ssridhar/Downloads/act-trproxy/act_trproxy.ko
   #sudo insmod /home/istguser1/QE-ACT-5.0/act_qe.ko

#echo "creating QE"
#create_qe \
#   $STARTING_QE_INDEX \
#   $ENDING_QE_INDEX

#echo "creating Police"
#create_police \
#   $STARTING_QE_INDEX \
#   $ENDING_QE_INDEX


echo "setup_single pair veth for imagedetect container."
  setup_single_paired_veth \
     ${veth_imagedetect_ns[0]} \
     ${veth_imagedetect_ns[1]} \
     ${veth_imagedetect_ns[2]} \
     ${veth_imagedetect_ns[3]}

 create_ingress_qdiscs \
     $MOB_IFACE

  create_egress_fq_qdiscs \
     $MOB_IFACE

 #create_qdiscs \
 #    ${veth_imagedetect_ns[2]}

  create_ingress_qdiscs \
     ${veth_imagedetect_ns[0]}

  create_egress_fq_qdiscs \
     ${veth_imagedetect_ns[0]}

  create_ingress_qdiscs \
     ${veth_imagedetect_ns[2]}

  create_egress_fq_qdiscs \
     ${veth_imagedetect_ns[2]}

echo "setup veth for swapping"
  setup_single_paired_veth \
     $VETH_SWAP1 \
     $VETH_SWAP1_MAC \
     $VETH_SWAP2 \
     $VETH_SWAP2_MAC

  create_ingress_qdiscs \
     $VETH_SWAP1

  create_egress_prio_qdiscs \
     $VETH_SWAP1

  echo "Setting up tc rules for veth swap for $MOBILE_TRAFFIC_SRC." 
  create_tc_actions_on_veth_swap \
   $MOBILE_TRAFFIC_SRC \
   $VETH_SWAP1 \
   1

  echo "Setting up tc rules for veth swap for $MOBILE_TRAFFIC_SRC2." 
  create_tc_actions_on_veth_swap \
   $MOBILE_TRAFFIC_SRC2 \
   $VETH_SWAP1 \
   10

 echo "Setting up tc rules for veth swap for $MOBILE_TRAFFIC_SRC3." 
  create_tc_actions_on_veth_swap \
   $MOBILE_TRAFFIC_SRC3 \
   $VETH_SWAP1 \
   20

echo "setup name space for $IMAGE_DETECT_NAMESPACE."
  setup_single_veth_namespace_container \
     7 \
     $IMAGE_DETECT_NAMESPACE \
     ${veth_imagedetect_ns[2]} \
     ${veth_imagedetect_ns[0]} \
     $IMAGE_DETECT_MOB_HOST_IP_ADDR \
     $IMAGE_DETECT_CONT_IP_ADDR

  echo "Setting up tc rules on interface $MOB_IFACE." 
  create_tc_actions_on_specified_veth \
      $MOB_IFACE \
      $IMAGE_DETECT_DEST_IP_ADDR \
      ${veth_imagedetect_ns[0]} \
      $MOB_MAC \
      ${veth_imagedetect_ns[3]} \
      $IMAGE_DETECT_PORT

  echo "setting up tc rules to route traffic from $MOBILE_TRAFFIC_SRC to host and $VETH_SWAP1"
  route_the_packets_to_host_and_veth_swap \
      $MOB_IFACE \
      10 \
      $MOBILE_TRAFFIC_SRC \
      $VETH_SWAP1 \
      $LOCAL_HOST


  echo "setting up tc rules to route traffic from $MOBILE_TRAFFIC_SRC2 to host and $VETH_SWAP1"
  route_the_packets_to_host_and_veth_swap \
      $MOB_IFACE \
      20 \
      $MOBILE_TRAFFIC_SRC2 \
      $VETH_SWAP1 \
      $LOCAL_HOST

  echo "setting up tc rules to route traffic from $MOBILE_TRAFFIC_SRC3 to host and $VETH_SWAP1"
  route_the_packets_to_host_and_veth_swap \
      $MOB_IFACE \
      30 \
      $MOBILE_TRAFFIC_SRC3 \
      $VETH_SWAP1 \
      $LOCAL_HOST


  echo "Setting up tc rules for Image detect host interface ${veth_imagedetect_ns[0]}"
  create_tc_actions_on_image_processing_host_interface \
      ${veth_imagedetect_ns[0]} \
      $MOB_IFACE \
      $IMAGE_DETECT_PORT \
      $MOB_MAC \
      $MOB_MAC_OF_NEXT_HOP

  echo "Setting up tc rules for Image detect container interface ${veth_imagedetect_ns[2]}"
  create_tc_actions_on_imagedetect_container_interface \
      ${veth_imagedetect_ns[2]} \
      $IMAGE_DETECT_PORT \
      $IMAGE_DETECT_NAMESPACE \
      $IMAGE_DETECT_PORT

  #echo "Launching $IMAGE_PROCESSING_PYTHON_SCRIPT script to read a text file and send the content to a server in AWS."  
  #sudo nohup $IMAGE_PROCESSING_PYTHON_SCRIPT &


  echo "Launching $IMAGE_PROCESSING_APPLICATION in $IMAGE_DETECT_NAMESPACE container to catch all jpeg images."  
  sudo $IP netns exec $IMAGE_DETECT_NAMESPACE nohup $IMAGE_PROCESSING_APPLICATION &

  echo "Launching $IMAGE_PROCESSING_SHELL_SCRIPT in $IMAGE_DETECT_NAMESPACE container to convert the captured images into characters and write it to a file."
  sudo $IP netns exec $IMAGE_DETECT_NAMESPACE nohup $IMAGE_PROCESSING_SHELL_SCRIPT &

  echo "Launching $KAON_VERIZON_DEMO"
  sudo nohup $KAON_VERIZON_DEMO &

  #echo "Deleting trace.out"
  #sudo rm -f trace.out

}

nobypass_infrastructure() {
  echo "Setting up tc rules on interface $MOB_IFACE."
  create_tc_actions_on_specified_veth \
      $MOB_IFACE \
      $IMAGE_DETECT_DEST_IP_ADDR \
      ${veth_imagedetect_ns[0]} \
      $MOB_MAC \
      ${veth_imagedetect_ns[3]} \
      $IMAGE_DETECT_PORT
}


bypass_infrastructure() {
  echo "Deleting tc rules on interface $MOB_IFACE for $IMAGE_DETECT_DEST_IP_ADDR:$IMAGE_DETECT_PORT." 
  $TC filter del dev $MOB_IFACE prio 1 parent ffff:
}

teardown_infrastructure() {
  echo "Deleting namespace $IMAGE_DETECT_NAMESPACE"
  $IP netns del $IMAGE_DETECT_NAMESPACE

  #delete_qdiscs \
  #   $MOB_IFACE

  delete_qdiscs \
     $IMAGE_HOST_VETH

  delete_qdiscs \
     $IMAGE_CONT_VETH

  delete_veth \
     $IMAGE_HOST_VETH \
     $IMAGE_CONT_VETH

  echo "Deleting tc filter rule 5 on ingress QDISC on $MOB_IFACE"
  sudo tc filter del dev $MOB_IFACE prio 5 parent ffff: 

  echo "Deleting ingress filters for MOB_IFACE"
  sudo tc filter del dev $MOB_IFACE parent ffff:

  echo "Deleting egress filters for MOB_IFACE"
  sudo tc filter del dev $MOB_IFACE parent 1:

  #echo "Deleting QE"
  #delete_qe \
  # $STARTING_QE_INDEX \
  # $ENDING_QE_INDEX

  #echo "Deleting Kernel modules"
  #sudo rmmod act_qe

  #echo "Deleting Police"
  #delete_police \
  # $STARTING_QE_INDEX \
  # $ENDING_QE_INDEX

  echo "killing server"
  sudo pkill "server"
  
  echo "killing start-server.sh"
  sudo pkill -f "start-server.sh"

  delete_veth \
     $VETH_SWAP1 \
     $VETH_SWAP2

  echo "Deleting ingress filters for $VETH_SWAP1"
  sudo tc filter del dev $VETH_SWAP1 parent ffff:

  echo "Deleting egress filters for $VETH_SWAP1"
  sudo tc filter del dev $VETH_SWAP1 parent 1:

  delete_qdiscs \
     $VETH_SWAP1

  echo "Stopping $KAON_VERIZON_DEMO"
  sudo pkill -f "runudpmultiplexer.sh"  
  sudo pkill -9 -f "udpmultiplexer.jar"

  #echo "Deleting $IMAGE_PROCESSING_PYTHON_SCRIPT"  
  #sudo pkill python3.6
}

#
# $1 - endpoint to dump stats at
# $2 - namespace id
show_infrastructure() {
#  show_infrastructure_actions
  if [ "$1" == "ifmob-in" ]; then
$TC -s filter ls dev $MOB_IFACE parent ffff:
  elif [ "$1" == "ifmob-out" ]; then
$TC -s filter ls dev $MOB_IFACE parent 1:
  elif [ "$1" == "qdisc" ]; then
$TC -s qdisc ls
  elif [ "$1" == "nsqdisc" ]; then
$TC -n $2 -s qdisc ls
  elif [ "$1" == "imagehost-in" ]; then
$TC -s filter ls dev $IMAGE_HOST_VETH parent ffff:
  elif [ "$1" == "imagehost-out" ]; then
$TC -s filter ls dev $IMAGE_HOST_VETH parent 1:
  elif [ "$1" == "imagecont-in" ]; then
$IP netns exec $IMAGE_DETECT_NAMESPACE $TC -s filter ls dev $IMAGE_CONT_VETH parent ffff:
  elif [ "$1" == "imagecont-out" ]; then
$IP netns exec $IMAGE_DETECT_NAMESPACE $TC -s filter ls dev $IMAGE_CONT_VETH parent 1:
  elif [ "$1" == "vethswp-in" ]; then
$TC -s filter ls dev $VETH_SWAP1 parent ffff:
  elif [ "$1" == "vethswp-out" ]; then
$TC -s filter ls dev $VETH_SWAP1 parent 1:
  fi
}

case "$1" in
  start) create_infrastructure ;;
  stats) show_infrastructure $2 $3 ;;
  stop) teardown_infrastructure ;;
  bypass) bypass_infrastructure ;;
  nobypass) nobypass_infrastructure ;;
  *) echo "usage: $0 start|stats <ifmob-in|ifmob-out|qdisc|imagehost-in|imagehost-out|imagecont-in|imagecont-out|vethswp-in|vethswp-out|nsqdisc> <NS>|stop|bypass|nobypass"
     exit 1
     ;;
esac

