#!/bin/bash

function header(){
    echo    '#   ____  _____  _  _  _  _      __    ____ '
    echo    '#  (  _ \(  _  )( \/ )( \/ )    /__\  (  _ \'
    echo    '#   )   / )(_)(  )  (  \  /    /(__)\  )___/'
    echo    '#  (_)\_)(_____)(_/\_) (__)   (__)(__)(__)  '
    echo    '#'
}

##print with color
NC='\033[0m' # No Color
function echo_e(){
	case $1 in 
		red)	echo -e " \033[0;31m $2 ${NC} " ;;
		green) 	echo -e " \033[0;32m $2 ${NC} " ;;
		yellow) echo -e " \033[0;33m $2 ${NC} " ;;
		blue)	echo -e " \033[0;34m $2 ${NC} " ;;
		purple)	echo -e " \033[0;35m $2 ${NC} " ;;
		cyan) 	echo -e " \033[0;36m $2 ${NC} " ;;
		*) echo $1;;
	esac
	
}

#check packages are installed
function is_installed(){
	PACKAGE=$1
	IS_INSTALLED=$(dpkg --get-selections | grep -w $PACKAGE | grep -w install)
	if [ "$IS_INSTALLED" = "" ]; then
		echo_e red "[-] $PACKAGE  not installed..."
		apt-get install -y $PACKAGE
	else
		echo_e green "[+]  $PACKAGE  is installed"
	fi
}

#CONFIGURE INTERFACES
#check interfaces/ configure DNS
i_interface="";
o_interface="";

function configure_dnsmasq(){   # $1 ip wifi[GATEWAY] $2 range1 $3 range2
	sudo ifconfig ${interface[$i_interface]} down
	sudo ifconfig ${interface[$i_interface]} $1
	sudo ifconfig ${interface[$i_interface]} up

	path_dnsmasq="/var/roxyap/dnsmasq.conf"
    if [ ! -f $path_dnsmasq ]
    then 
        mkdir -p /var/roxyap
    else
    	rm -rf $path_dnsmasq
    fi

	DNSCONFIG=$path_dnsmasq	
    echo "interface="${interface[$i_interface]}	    >>$DNSCONFIG
	echo "dhcp-range=$2,$3,255.255.255.0,24h"		>>$DNSCONFIG
}

function interfaces(){
	echo "Select interfaces"
	cont=0;
	for i in `ip link show|grep ^[0-9]| grep -v lo|cut -f2 -d":"|sed 's/^[ \t]*//'`
	do
		cont=`expr $cont + 1`
		interface[$cont]=$i
		echo_e green "[$cont] $i"
	done
	echo ""
	echo ""
	echo -n "Select Wifi interface: "
	read i_interface;
	echo -n "Select Ethernet interface: "
	read o_interface;
}

#CONFIGURE HOSTAP
path_hostap="/var/roxyap/hostap.conf"
function wpa2_hostap(){     # $1 wifi interface $2 ssid $3 password
	sudo rm -rf $path_hostap
    WIRELES=$path_hostap
	#file_config
	echo "interface=$1"				>>$WIRELES
	echo "driver=nl80211"			>>$WIRELES
	echo "ssid=$2"					>>$WIRELES
	echo "hw_mode=g"				>>$WIRELES
	echo "channel=6"				>>$WIRELES
	echo "auth_algs=1"				>>$WIRELES
	echo "macaddr_acl=0"			>>$WIRELES
	echo "ignore_broadcast_ssid=0"	>>$WIRELES
	echo "wpa=3"					>>$WIRELES
	echo "wpa_passphrase=$3"		>>$WIRELES
	echo "wpa_key_mgmt=WPA-PSK"		>>$WIRELES
	echo "wpa_pairwise=TKIP"		>>$WIRELES
	echo "rsn_pairwise=CCMP"		>>$WIRELES
}

function open_hostap(){     # $1 wifi interface $2 ssid 
        sudo rm -rf $path_hostap
    	WIRELES=$path_hostap
	#file_config
	echo "interface=$1"				>>$WIRELES
	echo "driver=nl80211"			>>$WIRELES
	echo "ssid=$2"					>>$WIRELES
	echo "hw_mode=g"				>>$WIRELES
	echo "channel=6"				>>$WIRELES
}

#METHODS MENU

function configure_AP(){
	echo ""
	echo echo "If password empty, open wify"
	echo ""
	echo -ne "SSID: "
	read ssid
	echo -ne "password: "
	read password
	echo ""
	echo -ne "Configure hostap? (s/n): "
    read confirm 
    case $confirm in 
        n) ;;
        *) 
		if [ $password ]
		then
			wpa2_hostap ${interface[$i_interface]} $ssid $password
		else
			open_hostap ${interface[$i_interface]} $ssid 
		fi
		;;
    esac	
}

function configure_IP_DNS (){
    echo "";
    echo -ne "Wifi IP [ex: 192.168.8.1]: "
    read gateway
    echo -ne "Start range [ex: 192.168.8.10]: "
    read start_range
    echo -ne "End range [ex: 192.168.8.100]: "
    read end_range
    echo ""
    echo -ne "Configure interfaces? (s/n): "
    read confirm 
    case $confirm in 
        n) ;;
        *) configure_dnsmasq $gateway $start_range $end_range;;
    esac
    clear
}

#iptables 
function iptables_forward(){

	sudo bash -c 'echo 1 > /proc/sys/net/ipv4/ip_forward'

	iptables -F
	iptables -t nat -F
	iptables -A FORWARD -i $i_interface -o $o_interface -j ACCEPT
	iptables -t nat -A POSTROUTIN -o $o_interface -j MASQUERADE
}

function run(){

	#kill proceess that use dns port

	echo_e yellow "[-] Preparing configuration ..."
	for	i in `sudo netstat -patun | grep 53 | tr -s " " " " | cut -d" " -f 6 | grep "/" | cut -d"/" -f 1`
	do 
		sudo kill -9 $i
	done 
	echo_e green "[+] Process on port 53 are killed ..."
	hostapd $path_hostap & 
	sudo dnsmasq -d -C $path_dnsmasq

}



#MAIN
# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

function ctrl_c() {
    echo ""
	echo_e red "[-] Stopping services"
	
	sudo service hostapd stop
	sudo service dnsmasq stop

	#kill process dnsmasq
	for i in `ps aux | grep dnsmasq | tr -s " " " " | grep root | cut -f2 -d" "`
	do 
		sudo kill -9  $i
	done
	echo_e yellow "[-] dnsmasq stoped"

	#kill process hostapd
    for i in `ps aux | grep hostapd | tr -s " " " " | grep root | cut -f2 -d" "`
    do 
            sudo kill -9  $i
    done
	echo_e yellow "[-] hostapd stoped"

	sudo bash -c 'echo 0 > /proc/sys/net/ipv4/ip_forward'
	echo_e yellow "[-] restart forward stoped"

	iptables -F
	iptables -t nat -F
	echo_e yellow "[-] iptables cleared"

	echo_e yellow "Exiting ..."
	exit
}


##check root
if [ $(id -u) = 0 ]
then
	echo  ">>Roxan v2.0"
else
	echo "You must be root to acces"
	exit 1
fi 

##check dependency
#sleep 1
is_installed net-tools
is_installed hostapd
is_installed dnsmasq
is_installed aircrack-ng

header
interfaces
configure_dnsmasq 192.168.8.1 192.168.8.90 192.168.8.200
#dfault settingsd
echo_e yellow " [-] Default Wireles input ip 192.168.8.1"
echo_e yellow " [-] Default dnsmasq range ip 192.168.8.90-100"
sleep 1

#option menu 

while [ true ]
do
clear
echo ""
echo "Menu"
echo "1.Configure access point"
echo "2.Configure WirelesIP DNS"
echo "?.Start roxyAP"
echo ""
echo -ne "seleccionar : " 
read option
clear
case $option in 
	1) configure_AP ;;
	2) configure_IP_DNS ;;
	80) run;;
	*) echo_e red "Debes seleccionar "
esac
clear
done

