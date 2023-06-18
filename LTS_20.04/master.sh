#!/bin/bash

# Get the name of the default network interface
default_interface=$(ip route show default | awk '{print $5}')

# Get the IP address of the default network interface
ip_address=$(ip addr show $default_interface | awk '/inet/ {print $2}')

# Check if the IP address starts with 10
if [[ $ip_address =~ ^10 ]]; then
    underlay="10.10.0.0/16"
    overlay="192.168.0.0/16"
else
    underlay="192.168.0.0/16"
    overlay="10.10.0.0/16"
fi

# Print the Networks
echo "Underlay network is $underlay and Overlay network is $overlay"

ip_address_short=$(echo "$ip_address" | cut -d'/' -f1 |head -n 1)
#sudo echo "$ip_address_short master" >> /etc/hosts
echo "$ip_address_short master" | sudo tee -a /etc/hosts
echo "how much workers you want to attach"
read num

if [[ $num -gt 0 ]]; then
    # Loop through the number of workers and print them
    for i in $(seq 1 $num); do
        echo "enter ip of worker$i"
        read ip
        #sudo echo "$ip worker" >> /etc/hosts
        echo "$ip worker" | sudo tee -a /etc/hosts
    done
else
    echo "Please enter a valid number of workers."
fi

sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
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
sudo curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo curl -fsSL "https://packages.cloud.google.com/apt/doc/apt-key.gpg" | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/kubernetes-archive-keyring.gpg
sudo sh -c "echo 'deb https://packages.cloud.google.com/apt kubernetes-xenial main' > /etc/apt/sources.list.d/kubernetes.list"
sudo apt-get update
sudo apt install -y kubelet=1.26.5-00 kubeadm=1.26.5-00 kubectl=1.26.5-00 docker.io
sudo apt-mark hold kubelet kubeadm kubectl docker.io
sudo mkdir /etc/containerd
sudo sh -c "containerd config default > /etc/containerd/config.toml"
sudo systemctl restart containerd.service
sudo systemctl restart kubelet.service
sudo systemctl start docker.service
sudo systemctl enable kubelet.service
#sudo systemctl enable docker.service
sudo kubeadm config images pull
sudo kubeadm init --pod-network-cidr=$overlay
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/tigera-operator.yaml
curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/custom-resources.yaml -O
sed -i "s|192.168.0.0\/16|$overlay|g" custom-resources.yaml
kubectl create -f custom-resources.yaml
kubeadm token create --print-join-command