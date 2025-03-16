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
    else
        echo "selinux is already altered"
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
    else
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
    else
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
        sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
        dnf install -y docker-ce docker-compose-plugin docker-ce-cli
        systemctl enable docker
        systemctl start docker
    else
        echo "docker is already installed"
        docker ps
    fi

    # Install Go
    echo "Installing Go programming language and git utility..."
    if ! command -v go &> /dev/null || ! command -v git &> /dev/null; then
        yum install -y go git wget
    else
        echo "both git and go installed already"
    fi

    # Build and install crio
    echo "Installing crio services..."
    if ! command -v crio &> /dev/null || [[ ! -f /etc/yum.repos.d/cri-o.repo ]]; then
        CRIO_VERSION=v1.30
        cat <<EOF | tee /etc/yum.repos.d/cri-o.repo
[cri-o]
name=CRI-O
baseurl=https://pkgs.k8s.io/addons:/cri-o:/stable:/$CRIO_VERSION/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/addons:/cri-o:/stable:/$CRIO_VERSION/rpm/repodata/repomd.xml.key
EOF
#        VERSION=1.22
#        sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/CentOS_8/devel:kubic:libcontainers:stable.repo
#        sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:${VERSION}.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:${VERSION}/CentOS_8/devel:kubic:libcontainers:stable:cri-o:${VERSION}.repo
        sudo dnf -y install cri-o
        sudo systemctl enable --now crio
        sudo systemctl start crio
    else
        echo "crio is already installed successfully"
        systemctl list-units | grep crio; crictl ps; cat /etc/crictl.yaml
        echo "all set from crio CRI prospective"

    fi

    # add cri socket endpoint to the crictl utilities
    if ! command -v crictl &> /dev/null || [[ ! -f /etc/crictl.yaml ]]; then
        echo "crictl is missing or /etc/crictl.yaml does not exist"
        wget https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.26.0/crictl-v1.26.0-linux-amd64.tar.gz
        sudo tar zxvf crictl-v1.26.0-linux-amd64.tar.gz -C /usr/bin
        cat <<EOF | tee /etc/crictl.yaml
runtime-endpoint: unix:///var/run/crio/crio.sock
image-endpoint: unix:///var/run/crio/crio.sock
timeout: 2
debug: false
EOF
        echo "checking crictl socket connectivity"
        crictl ps
    else
        echo "both crictl & crictl.yaml are already existed"
        crictl ps
    fi

    # Add Kubernetes repository
    echo "Adding Kubernetes repository..."
    if [[ ! -f /etc/yum.repos.d/kubernetes.repo ]]; then
        cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.32/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.32/rpm/repodata/repomd.xml.key
EOF
    else
       echo "kubernetes.repo is already existed"
    fi

    # Install Kubernetes components
    echo "Installing Kubernetes components..."
    if ! command -v kubeadm &> /dev/null || ! command -v kubectl &> /dev/null; then
        dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
        systemctl enable --now kubelet
        kubeadm version
        kubectl version --short
    else
        echo "kubeadm,kubectl already installed"
        kubeadm version
        kubectl version --short
    fi

    # Initialize Kubernetes cluster
    if [[ ! -f /etc/kubernetes/admin.conf ]]; then
        echo "Initializing Kubernetes cluster..."
#        kubeadm init --apiserver-advertise-address $(hostname -i) --pod-network-cidr=192.168.0.0/16
        kubeadm init --pod-network-cidr=192.168.0.0/16 --cri-socket=unix:///var/run/crio/crio.sock --ignore-preflight-errors=SystemVerification,FileExisting-tc,Firewalld


        # Deploy Calico network plugin
        echo "Deploying Calico network plugin..."
        wget https://docs.projectcalico.org/manifests/calico.yaml
        kubectl apply -f calico.yaml

        # Configure kubectl for the root user
        echo "Configuring kubectl for the root user..."
        mkdir -p $HOME/.kube
        cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
        chown $(id -u):$(id -g) $HOME/.kube/config
 #   elif [kubectl get no | grep -i ready]:
    else
         echo "Deploying Calico network plugin..."
         curl -L -O https://projectcalico.docs.tigera.io/manifests/calico.yaml
         kubectl apply -f calico.yaml

         echo "Configuring kubectl for the root user..."
         mkdir -p $HOME/.kube
         cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
         chown $(id -u):$(id -g) $HOME/.kube/config


    fi

    echo "Kubernetes installation completed successfully."
}

# Run the function
kube_installation

