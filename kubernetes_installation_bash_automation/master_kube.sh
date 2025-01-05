#!/bin/bash

kube_installation () {
    echo "Starting Kubernetes installation script..."

    # Update system packages
    echo "Updating system packages..."
    yum update -y

    # Disable SELinux temporarily and permanently
    if [[ $(getenforce) != "Permissive" ]]; then
        echo "Disabling SELinux..."
        setenforce 0
        sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
    fi

    # Load necessary kernel modules
    echo "Loading kernel modules..."
    modprobe overlay
    modprobe br_netfilter
    if [[ ! -f /etc/modules-load.d/k8s.conf ]]; then
        echo "Creating kernel module configuration file..."
        cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF 
    else:
        echo "kernel module is already loaded"
    fi

    # Configure sysctl for Kubernetes networking
    echo "Configuring sysctl for Kubernetes networking..."
    if [[ ! -f /etc/sysctl.d/k8s.conf ]]; then
        cat > /etc/sysctl.d/k8s.conf << EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
        sysctl --system
    else:
        echo "sysctl is loaded"
    fi

    # Disable swap
    echo "Disabling swap..."
    if [[ $(swapon --show) ]]; then
        swapoff -a
        sed -e '/swap/s/^/#/g' -i /etc/fstab
    fi

    # Install Docker
    echo "Installing Docker..."
    if ! command -v docker &> /dev/null; then
        dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
        dnf install -y docker-ce
        systemctl start docker
        systemctl enable docker
    fi

    # Install Go
    echo "Installing Go programming language and git utility..."
    if ! command -v go &> /dev/null && ! command -v git &> /dev/null; then
        yum install -y go git
    else:
        echo "both git and go installed already"
    fi

    # Build and install cri-dockerd
    echo "Installing cri-dockerd..."
    if ! command -v cri-dockerd &> /dev/null; then
        git clone https://github.com/Mirantis/cri-dockerd.git
        cd cri-dockerd
        mkdir bin
        go build -o bin/cri-dockerd
        mkdir -p /usr/local/bin
        install -o root -g root -m 0755 bin/cri-dockerd /usr/local/bin/cri-dockerd
        cp -a packaging/systemd/* /etc/systemd/system
        sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service
        systemctl daemon-reload
        systemctl enable cri-docker.service
        systemctl enable --now cri-docker.socket
    fi

    # Add Kubernetes repository
    echo "Adding Kubernetes repository..."
    if [[ ! -f /etc/yum.repos.d/kubernetes.repo ]]; then
        cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF
    fi

    # Install Kubernetes components
    echo "Installing Kubernetes components..."
    if ! command -v kubeadm &> /dev/null; then
        dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
        systemctl enable --now kubelet
    fi

    # Initialize Kubernetes cluster
    if [[ ! -f /etc/kubernetes/admin.conf ]]; then
        echo "Initializing Kubernetes cluster..."
        kubeadm init --apiserver-advertise-address $(hostname -i) --pod-network-cidr=192.168.0.0/16

        # Deploy Calico network plugin
        echo "Deploying Calico network plugin..."
        wget https://docs.projectcalico.org/manifests/calico.yaml
        kubectl apply -f calico.yaml

        # Configure kubectl for the root user
        echo "Configuring kubectl for the root user..."
        mkdir -p $HOME/.kube
        cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
        chown $(id -u):$(id -g) $HOME/.kube/config
    fi

    echo "Kubernetes installation completed successfully."
}

# Run the function
kube_installation


