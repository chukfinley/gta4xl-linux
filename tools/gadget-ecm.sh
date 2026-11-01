#!/bin/sh
# Rebuild the initramfs USB gadget as ECM + ACM only (Samsung's NCM never transmits,
# and mass storage alongside ECM breaks the bulk endpoints).
G=/sys/kernel/config/usb_gadget/g1
sleep 1
echo "" > $G/UDC
rm -f $G/configs/c.1/ncm.usb0 $G/configs/c.1/mass_storage.0 $G/configs/c.1/acm.usb0
mkdir -p $G/functions/ecm.usb0
echo 02:47:54:41:34:01 > $G/functions/ecm.usb0/dev_addr 2>/dev/null
echo 02:47:54:41:34:02 > $G/functions/ecm.usb0/host_addr 2>/dev/null
[ -e $G/configs/c.1/ecm.usb0 ] || ln -s $G/functions/ecm.usb0 $G/configs/c.1/
ln -s $G/functions/acm.usb0 $G/configs/c.1/
ls /sys/class/udc | head -n 1 > $G/UDC
sleep 2
IF=$(cat $G/functions/ecm.usb0/ifname)
ip addr replace 172.16.42.1/24 dev "$IF"
ip link set "$IF" up
killall telnetd 2>/dev/null
telnetd -b 172.16.42.1:23 -l /bin/sh
echo "initramfs: switched to $IF" > /dev/kmsg
