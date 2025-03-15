#!/bin/bash
echo "Welcome To One Click Worker Setup"
# Get the name of the default network interface
default_interface=$(ip route show default | awk '{print $5}')

# Get the IP address of the default network interface
ip_address=$(ip addr show $default_interface | awk '/inet/ {print $2}')

ip_address_short=$(echo "$ip_address" | cut -d'/' -f1 |head -n 1)
echo "$ip_address_short $(hostname)" | sudo tee -a /etc/hosts
echo "Enter Master ip"
read master
echo "$master master" | sudo tee -a /etc/hosts
sudo swapoff -a
sudo sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl
sudo mkdir /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt install -y kubelet=1.28.1-1.1 kubeadm=1.28.1-1.1 kubectl=1.28.1-1.1 docker.io
sudo apt-mark hold kubelet kubeadm kubectl docker.io
sudo mkdir /etc/containerd
sudo sh -c "containerd config default > /etc/containerd/config.toml"
sudo systemctl enable containerd.service --now
sudo systemctl enable kubelet.service --now
echo "Enter master join token"
read join
sudo $join
