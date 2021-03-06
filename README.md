A New Light Weight Architecture of Mobile Edge Computing
---------------------------------------------------------

Description:
------------
Multi-access edge computing (MEC), recently introduced by ETSI industry Specification Group (ISG), is a network architecture that offers cloud-computing capabilities within the RAN or core network in the cellular world to allow processing of tasks closer to the cellular customer. It has, however, evolved to be generic to apply to any network for deploying applications and services as well as to store and process content in close proximity to mobile users.
Current MEC solutions require either:
 	
	a) deploying a specialized (often proprietary) mobile edge platform	
	b) modifying existing applications (known as application splitting).

A light weight mobile edge computing architecture which utilizes existing Linux kernel mechanisms, namely: Traffic Control (TC) utilities, and network Namespaces are used in this edge compute application (openALPR) hosted on MEC.

This solution is able to:

	1. Deploy real-time applications onto mobile edge  device without any modification to meet their low
     latency requirements;
 	2. Provide computational offloading from either  battery powered mobile devices or back end
     services in cloud;
	3. Potentially convert any Linux based network devices   (e.g. Wifi router, eNodeB) into application server without introducing new hardware.


OPEN ALPR - Mobile Edge Computing (MEC) Proof of Concept(POC):
--------------------------------------------------------------

This POC shows how linux traffic controller and linux namespace controller is used do route packets from a mobile phone to an edge compute network that runs automatic license plate recognition algorithm to figure out the license plate from a JPEG image.

Here a custom built android app running on a smartphone is used to emulate a traffic camera that captures and sends a jpeg image of a vehicle which displays license plate.

Note that the SIM card on the phone is configured in such a way that the packet gateway always assigns a natted static ipv4 address to this SIM and that all the packets shall be pinned to a mobile edge computing platform and shall not be allowed to directly reach the internet.
![](arch.png)

TEST ENVIRONMENT:
----------------
![](openalpr.png)

STEP 1:
-------
Set up ingress and egress QDISC on the network interface card on the X86 card to where the mobile phone traffic is routed to.

![](step1.png)

STEP 2:
-------
Create a virtual ethernet pair IMAGE_HOST_VETH : IMAGE_CONT_VETH.
We will refer IMAGE_HOST_VETH as the veth that is exposed to the host and IMAGE_CONT_VETH as the veth that is exposed into a namespace container.

![](step2.png)

    1. ip link add IMAGE_HOST_VETH address 70:11:00:00:00:00 type veth peer name IMAGE_CONT_VETH
    2. ip link set IMAGE_CONT_VETH address 70:00:00:00:00:00
    3. ip link set IMAGE_HOST_VETH up mtu 32768
    4. ip link set IMAGE_CONT_VETH up mtu 32768
    5. tc qdisc add dev IMAGE_HOST_VETH root handle 1: fq
    6. tc qdisc add dev IMAGE_CONT_VETH root handle 1: fq
    7. tc qdisc add dev IMAGE_HOST_VETH ingress
    8. tc qdisc add dev IMAGE_CONT_VETH ingress

STEP 3:
-------

Set up a namespace container as shown below.

![](step3.png)


    1. ip netns add imagedetection
    2. ip -n imagedetection link set dev lo up
    3. ip link set dev IMAGE_CONT_VETH netns imagedetection
    4. ip -n imagedetection link set dev IMAGE_CONT_VETH mtu 32768
    5. ip -n imagedetection link set dev IMAGE_CONT_VETH up
    6. ip netns exec imagedetection sudo sh -c "echo 0 > /proc/sys/net/ipv4/conf/IMAGE_CONT_VETH/rp_filter
    7. ip netns exec imagedetection sudo sh -c "echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter"
    8. ip netns exec imagedetection sysctl -w net.ipv4.tcp_fwmark_accept=1
    9. ip netns exec imagedetection sysctl -w net.ipv4.fwmark_reflect=1
    10. ip -n imagedetection rule add iif IMAGE_CONT_VETH lookup 100
    11. ip -n imagedetection -6 rule add iif IMAGE_CONT_VETH lookup 100 
    12. ip -n imagedetection route add local 0.0.0.0/0 dev lo table 100
    13. ip -n imagedetection addr add 150.0.0.1/16 dev IMAGE_CONT_VETH
    14. ip -n imagedetection route add default via 150.0.0.2
    15. ip addr add 150.0.0.2/16 dev IMAGE_HOST_VETH
    16. sudo sh -c "echo 0 > /proc/sys/net/ipv4/conf/IMAGE_HOST_VETH/rp_filter"
    17. sudo sh -c "echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter"
    18. ip netns exec imagedetection ip link set IMAGE_CONT_VETH arp off
    19. sudo sh -c "ip link set IMAGE_HOST_VETH arp off"


STEP 4:
-------

Setup tc rules on the ingress QDISC of eth0 where packets from external world (Mobile phone) are queued up.

![](step4.png)


    tc filter add dev eth0 parent ffff: prio 1 protocol ip u32 \
    match ip protocol 0x6 0xff \
    match u8 0x6 0xff at 33 \
    match ip sport 12345 0xff \
    action skbedit ptype host \
    action skbmod dmac 70:00:00:00:00:00 \
    action skbmod smac 70:11:00:00:00:00 \
    action mirred egress redirect dev IMAGE_HOST_VETH



	Verification command: /sbin/tc -s filter ls dev eth0 parent ffff:
	-----------------------------------------------------------------
    filter protocol ip pref 1 u32 chain 0 
    filter protocol ip pref 1 u32 chain 0 fh 800: ht divisor 1 
    filter protocol ip pref 1 u32 chain 0 fh 800::800 order 2048 key ht 800 bkt 0 terminal flowid ??? not_in_hw 
      match 00060000/00ff0000 at 8
      match 00000039/000000ff at 20
	
	action order 1: skbmod pipe set smac 5c:b9:01:c3:d9:38 
	  index 13 ref 1 bind 1 installed 9031 sec used 849 sec
	Action statistics:
	Sent 2459206 bytes 1764 pkt (dropped 0, overlimits 0 requeues 0) 
	backlog 0b 0p requeues 0 
	
	action order 2: skbmod pipe set dmac 70:00:00:00:00:00 
	 index 14 ref 1 bind 1 installed 9031 sec used 849 sec
	Action statistics:
	Sent 2459206 bytes 1764 pkt (dropped 0, overlimits 0 requeues 0) 
	backlog 0b 0p requeues 0 
	
	action order 3:  skbedit ptype host pipe
	 index 7 ref 1 bind 1 installed 9031 sec used 849 sec
 	Action statistics:
	Sent 2459206 bytes 1764 pkt (dropped 0, overlimits 0 requeues 0) 
	backlog 0b 0p requeues 0 
	
	action order 4: mirred (Egress Redirect to device IMAGE_HOST_VETH) stolen
 	index 7 ref 1 bind 1 installed 9031 sec used 849 sec
 	Action statistics:
	Sent 2459206 bytes 1764 pkt (dropped 0, overlimits 0 requeues 0) 
	backlog 0b 0p requeues 0 


STEP 5:
-------
Set up tc rules on the ingress QDISC on the VETH plugged into the namespace container. These tc rules can be used to accept the packet and also identify flags in the L4 protocol (TCP SYN, ACK…)

![](step5.png)

	MATCH TCP SYN AND ACCEPT IT.                          
	-----------------------------
	tc -n imagedetection filter add dev IMAGE_CONT_VETH prio 1 parent ffff: protocol ip u32 \
	match ip protocol 0x6 0xff \
	match u8 0x2 0xff at 33 \
	match ip dport 12345 0xff \
	action skbedit ptype host

  	MATCH TCP ACK AND ACCEPT IT.
  	----------------------------
    	tc -n imagedetection filter add dev IMAGE_CONT_VETH prio 2 parent ffff: protocol ip u32 \
        match ip protocol 0x6 0xff \
        match u8 0x10 0xff at 33 \
        match ip dport 12345 0xff \
        action skbedit ptype host

  	MATCH TCP ACCEPT IT.
  	--------------------
    tc -n imagedetection filter add dev IMAGE_CONT_VETH prio 3 parent ffff: protocol ip u32 \
        match ip protocol 0x6 0xff \
        match ip dport 12345 0xff \
        action skbedit ptype host

	Verification command : ip netns exec imagedetection tc -s filter ls dev IMAGE_CONT_VETH parent ffff:
	----------------------------------------------------------------------------------------------------
    filter protocol ip pref 1 u32 chain 0 
    filter protocol ip pref 1 u32 chain 0 fh 800: ht divisor 1 
    filter protocol ip pref 1 u32 chain 0 fh 800::800 order 2048 key ht 800 bkt 0 terminal flowid ??? not_in_hw 
    match 00060000/00ff0000 at 8
    match 00020000/00ff0000 at 32
    match 00000039/000000ff at 20
	  action order 1:  skbedit ptype host pipe
	  index 1 ref 1 bind 1 installed 8963 sec used 783 sec
 	  Action statistics:
	  Sent 60 bytes 1 pkt (dropped 0, overlimits 0 requeues 0) 
	  backlog 0b 0p requeues 0 

    filter protocol ip pref 2 u32 chain 0 
    filter protocol ip pref 2 u32 chain 0 fh 801: ht divisor 1 
    filter protocol ip pref 2 u32 chain 0 fh 801::800 order 2048 key ht 801 bkt 0 terminal flowid ??? not_in_hw 
    match 00060000/00ff0000 at 8
    match 00100000/00ff0000 at 32
    match 00000039/000000ff at 20
	  action order 1:  skbedit ptype host pipe
	  index 2 ref 1 bind 1 installed 8963 sec used 781 sec
 	  Action statistics:
	  Sent 2401036 bytes 1721 pkt (dropped 0, overlimits 0 requeues 0) 
	  backlog 0b 0p requeues 0 

    filter protocol ip pref 3 u32 chain 0 
    filter protocol ip pref 3 u32 chain 0 fh 802: ht divisor 1 
    filter protocol ip pref 3 u32 chain 0 fh 802::800 order 2048 key ht 802 bkt 0 terminal flowid ??? not_in_hw 
    match 00060000/00ff0000 at 8
    match 00000039/000000ff at 20
	  action order 1:  skbedit ptype host pipe
	  index 3 ref 1 bind 1 installed 8962 sec used 781 sec
 	  Action statistics:
	  Sent 58110 bytes 42 pkt (dropped 0, overlimits 0 requeues 0) 
	  backlog 0b 0p requeues 0 

STEP 6
-------
Set up tc rules on the ingress QDISC VETH exposed to the local host on x86 card to route the packets (TCP SYN ACK, FIN, FIN ACK,...) originating from the imagedetection namespace container back to the mobile phone.

![](step6.png)

	MATCH TCP PROTOCOL and SOURCE PORT 12345,
	-----------------------------------------
	match the TCP FLAG SYN ACK,
	---------------------------
	set the source MAC as the MAC address of eth0
	----------------------------------------------
	and dest mac as the MAC address of the next hop (EDGE router).
	--------------------------------------------------------------
	tc filter add dev IMAGE_HOST_VETH parent ffff: prio 1 protocol ip u32 \
	match ip protocol 0x6 0xff \
	match ip sport 12345 0xff \
	match u8 0x12 0xff at 33 \
	action skbedit ptype host \
	action skbmod dmac e4:d3:f1:b1:b4:83 \
	action skbmod smac 5c:b9:01:c3:d9:38 \
	action mirred egress redirect dev eth0


	
    MATCH TCP PROTOCOL, FOR ALL OTHER FLAGS, set SOURCE PORT 12345, 
    ---------------------------------------------------------------
    set the source MAC as the MAC address of eth0
    ----------------------------------------------
    and dest mac as the MAC address of the next hop (EDGE router).
    ---------------------------------------------------------------

    tc filter add dev IMAGE_HOST_VETH parent ffff: prio 2 protocol ip u32 \
                        match ip protocol 0x6 0xff \
                        match ip sport 12345 0xff \
                        match u8 0x12 0xff at 33 \
                        action skbedit ptype host \
                        action skbmod dmac e4:d3:f1:b1:b4:83 \
                        action skbmod smac 5c:b9:01:c3:d9:38 \
                        action mirred egress redirect dev eth0

	Verification command : tc -s filter ls dev IMAGE_HOST_VETH parent ffff:
	-----------------------------------------------------------------------

    filter protocol ip pref 1 u32 chain 0 
    filter protocol ip pref 1 u32 chain 0 fh 800: ht divisor 1 
    filter protocol ip pref 1 u32 chain 0 fh 800::800 order 2048 key ht 800 bkt 0 terminal flowid ??? not_in_hw 
    match 00060000/00ff0000 at 8
    match 00120000/00ff0000 at 32
    match 00390000/00ff0000 at 20
	  
	  action order 1:  skbedit ptype host pipe
	  index 17 ref 1 bind 1 installed 8923 sec used 743 sec
 	  Action statistics:
	  Sent 60 bytes 1 pkt (dropped 0, overlimits 0 requeues 0) 
	  backlog 0b 0p requeues 0 
	  
	  action order 2: skbmod pipe set dmac e4:d3:f1:b1:b4:83 
	  index 15 ref 1 bind 1 installed 8923 sec used 743 sec
	  Action statistics:
	  Sent 60 bytes 1 pkt (dropped 0, overlimits 0 requeues 0) 
	  backlog 0b 0p requeues 0 
	  
	  action order 3: skbmod pipe set smac 5c:b9:01:c3:d9:38 
	  index 16 ref 1 bind 1 installed 8923 sec used 743 sec
	  Action statistics:
	  Sent 60 bytes 1 pkt (dropped 0, overlimits 0 requeues 0) 
	  backlog 0b 0p requeues 0 
	  
	  action order 4: mirred (Egress Redirect to device eth0) stolen
 	  index 14 ref 1 bind 1 installed 8923 sec used 743 sec
 	  Action statistics:
	  Sent 60 bytes 1 pkt (dropped 0, overlimits 0 requeues 0) 
	  backlog 0b 0p requeues 0 

    filter protocol ip pref 2 u32 chain 0 
    filter protocol ip pref 2 u32 chain 0 fh 801: ht divisor 1 
    filter protocol ip pref 2 u32 chain 0 fh 801::800 order 2048 key ht 801 bkt 0 terminal flowid ??? not_in_hw 
    match 00060000/00ff0000 at 8
    match 00390000/00ff0000 at 20
	  
	  action order 1:  skbedit ptype host pipe
	  index 18 ref 1 bind 1 installed 8923 sec used 741 sec
 	  Action statistics:
	  Sent 53396 bytes 1010 pkt (dropped 0, overlimits 0 requeues 0) 
	  backlog 0b 0p requeues 0 
	  
	  action order 2: skbmod pipe set dmac e4:d3:f1:b1:b4:83 
	  index 17 ref 1 bind 1 installed 8923 sec used 741 sec
	  Action statistics:
	  Sent 53396 bytes 1010 pkt (dropped 0, overlimits 0 requeues 0) 
	  backlog 0b 0p requeues 0 
	  
	  action order 3: skbmod pipe set smac 5c:b9:01:c3:d9:38 
	  index 18 ref 1 bind 1 installed 8923 sec used 741 sec
	  Action statistics:
	  Sent 53396 bytes 1010 pkt (dropped 0, overlimits 0 requeues 0) 
	  backlog 0b 0p requeues 0 
	  
	  action order 4: mirred (Egress Redirect to device eth0) stolen
 	  index 15 ref 1 bind 1 installed 8923 sec used 741 sec
 	  Action statistics:
	  Sent 53396 bytes 1010 pkt (dropped 0, overlimits 0 requeues 0) 
	  backlog 0b 0p requeues 0 

