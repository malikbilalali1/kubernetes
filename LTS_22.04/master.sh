#!/bin/bash
echo "WELCOME TO ONE CLICK MASTER SETUP"
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
echo "$ip_address_short $(hostname)" | sudo tee -a /etc/hosts
while true; do
    read -rp "Enter the number of workers (0 to skip): " num
    if [[ ! $num =~ ^0$|^[1-9][0-9]*$ ]]; then
        echo "Error: Please enter a valid number."
        continue
    fi
    if [[ $num -eq 0 ]]; then
        echo "No workers will be added to /etc/hosts"
        break
    else
        for ((i=1; i<=num; i++)); do
            while true; do
                read -rp "Enter the IP of worker $i: " ip
                if [[ $ip =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
                    echo "worker$i $ip" | sudo tee -a /etc/hosts >/dev/null
                    break
                else
                    echo "Error: Invalid IP format. Please try again."
                fi
            done
        done
        echo "Successfully added $num worker(s) to /etc/hosts"
        break
    fi
done
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
sudo apt install -y kubelet=1.28.1-1.1 kubeadm=1.28.1-1.1 kubectl=1.28.1-1.1 containerd
sudo apt-mark hold kubelet kubeadm kubectl containerd
sudo mkdir /etc/containerd
sudo sh -c "containerd config default > /etc/containerd/config.toml"
sudo sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl enable containerd.service --now
sudo systemctl enable kubelet.service --now
sudo kubeadm config images pull
sudo kubeadm init --pod-network-cidr=$overlay
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml -O
sed -i "s|192.168.0.0\/16|$overlay|g" custom-resources.yaml
kubectl create -f custom-resources.yaml
kubeadm token create --print-join-command
