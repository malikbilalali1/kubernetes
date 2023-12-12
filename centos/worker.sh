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
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables
sysctl -a | grep net.bridge.bridge-nf-call-iptables

# Apply sysctl params without reboot
sudo sysctl --system

### Docker installation steps #######
sudo yum -y remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine buildah
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl start docker
sudo systemctl enable docker

### Kubernetes installation steps #####
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF
sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sudo systemctl enable kubelet
sudo systemctl start kubelet
#####################
######################
swapoff -a
echo "Enter master join token"
read join
sudo $join