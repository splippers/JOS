!/bin/sh

Bring up networking in initramfs

echo "JOS: Initialising network..."

Try DHCP on all interfaces
for iface in $(ls /sys/class/net); do
    echo "JOS: Attempting DHCP on $iface"
    udhcpc -i "$iface" -q -t 5
done
