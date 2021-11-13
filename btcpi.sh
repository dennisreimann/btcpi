#!/bin/bash
# Set BTCPayServer Environment Variables
export BTCPAY_HOST="btcpay.local"
export REVERSEPROXY_DEFAULT_HOST="$BTCPAY_HOST"
export NBITCOIN_NETWORK="mainnet"
export BTCPAYGEN_CRYPTO1="btc"
export BTCPAYGEN_LIGHTNING="lnd"
export BTCPAYGEN_REVERSEPROXY="nginx"
export BTCPAYGEN_ADDITIONAL_FRAGMENTS="opt-add-electrumx,opt-add-thunderhub"
export BTCPAY_ENABLE_SSH=true

# Configure External Storage
DEVICE_NAME=""
PARTITION_NAME=""
MOUNT_DIR="/mnt/external"
DOCKER_VOLUMES="/var/lib/docker/volumes"

isSD=$(fdisk -l | grep -c "/dev/mmcblk0:")
isNVMe=$(fdisk -l | grep -c "/dev/nvme0n1:")
isUSB=$(fdisk -l | grep -c "/dev/sda:")

# If booting from SD with external storage
if [ ${isSD} -eq 1 ] && [ ${isUSB} -eq 1 ]; then
  DEVICE_NAME="sda"
  PARTITION_NAME="sda1"
elif [ ${isSD} -eq 1 ] && [ ${isNVMe} -eq 1 ]; then
  DEVICE_NAME="nvme0n1"
  PARTITION_NAME="nvme0n1p1"
fi

if [ -n "${DEVICE_NAME}" ]; then
mkdir -p ${MOUNT_DIR}
sfdisk --delete /dev/${DEVICE_NAME}
sync
sleep 4
sudo wipefs -a /dev/${DEVICE_NAME}
sync
sleep 4
partitions=$(lsblk | grep -c "─${DEVICE_NAME}")
if [ ${partitions} -gt 0 ]; then
  dd if=/dev/zero of=/dev/${DEVICE_NAME} bs=512 count=1
  sync
fi
partitions=$(lsblk | grep -c "─${DEVICE_NAME}")
if [ ${partitions} -gt 0 ]; then
  exit 1
fi

(
echo o # Create a new empty DOS partition table
echo n # Add a new partition
echo p # Primary partition
echo 1 # Partition number
echo   # First sector (Accept default: 1)
echo   # Last sector (Accept default: varies)
echo w # Write changes
) | fdisk /dev/${DEVICE_NAME}
sync

# loop until the partition gets available
loopdone=0
loopcount=0
 while [ ${loopdone} -eq 0 ]
  do
  sleep 2
  sync
  loopdone=$(lsblk -o NAME | grep -c ${PARTITION_NAME})
  loopcount=$(($loopcount +1))
  if [ ${loopcount} -gt 10 ]; then
    exit 1
    fi
 done

mkfs.ext4 -F -L external /dev/${PARTITION_NAME} 
loopdone=0
loopcount=0
while [ ${loopdone} -eq 0 ]
 do
 sleep 2
 sync
 loopdone=$(lsblk -o NAME,LABEL | grep -c external)
 loopcount=$(($loopcount +1))
 if [ ${loopcount} -gt 10 ]; then
         exit 1
       fi
done

UUID="$(sudo blkid -s UUID -o value /dev/${PARTITION_NAME})"
echo "UUID=$UUID ${MOUNT_DIR} ext4 defaults,noatime,nofail 0 0" | tee -a /etc/fstab
mount /dev/${PARTITION_NAME} ${MOUNT_DIR}
sleep 5
rm -rf "$DOCKER_VOLUMES"
mkdir -p "$DOCKER_VOLUMES"
mount --bind "$MOUNT_DIR" "$DOCKER_VOLUMES"
echo "$MOUNT_DIR $DOCKER_VOLUMES none bind,nobootwait 0 2" >> /etc/fstab
systemctl restart docker
fi


# Configure Firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow from 10.0.0.0/8 to any port 22 proto tcp
ufw allow from 172.16.0.0/12 to any port 22 proto tcp
ufw allow from 192.168.0.0/16 to any port 22 proto tcp
ufw allow from 169.254.0.0/16 to any port 22 proto tcp
ufw allow from fc00::/7 to any port 22 proto tcp
ufw allow from fe80::/10 to any port 22 proto tcp
ufw allow from ff00::/8 to any port 22 proto tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 8333/tcp
ufw allow 9735/tcp
yes | ufw enable

# Disable Swapfile
dphys-swapfile swapoff
dphys-swapfile uninstall
update-rc.d dphys-swapfile remove
systemctl disable dphys-swapfile

# Install BTCPayServer
cd /root
git clone https://github.com/btcpayserver/btcpayserver-docker
cd btcpayserver-docker
. btcpay-setup.sh -i

# Update RaspiOS
apt update && apt upgrade -y 
apt autoremove -y
