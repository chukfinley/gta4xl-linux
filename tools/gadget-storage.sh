#!/bin/sh
# Live-reconfigure the initramfs gadget: ACM console + userdata as USB mass storage.
G=/sys/kernel/config/usb_gadget/g1
M=$G/functions/mass_storage.0
sleep 1
echo "" > $G/UDC
rm -f $G/configs/c.1/ecm.usb0 $G/configs/c.1/ncm.usb0 $G/configs/c.1/mass_storage.0 $G/configs/c.1/acm.usb0
mkdir -p $M
echo "" > $M/lun.0/file
echo 0 > $M/lun.0/cdrom
echo 0 > $M/lun.0/ro
echo 1 > $M/lun.0/removable
echo /dev/sda32 > $M/lun.0/file
ln -s $M $G/configs/c.1/
ln -s $G/functions/acm.usb0 $G/configs/c.1/
ls /sys/class/udc | head -n 1 > $G/UDC
echo "initramfs: gadget now acm + userdata storage ($(cat $M/lun.0/file))" > /dev/kmsg
