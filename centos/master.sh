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
    read -p "Enter the number of workers you want to attach: " num

    if [[ $num -gt 0 ]]; then
        for i in $(seq 1 $num); do
            echo "Enter the IP of worker $i:"
            read ip
            echo "$ip worker$i" | sudo tee -a /etc/hosts 
        done
        break  # Exit the loop if a valid number of workers is entered
    else
        echo "Please enter a valid number of workers."
    fi
done
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