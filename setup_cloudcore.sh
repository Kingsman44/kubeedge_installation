LOCAL_IP_ADDRESS=192.168.107.4 #master node

# Update
sudo apt-get update
sudo apt-get upgrade -y

# Install required files
sudo apt install apt-transport-https curl -y

# Install containerd and set containerd
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install containerd.io -y
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd

# Install Kubernetes
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
sudo apt install kubeadm kubelet kubectl kubernetes-cni -y

# Disable Swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Enable IP features
sudo modprobe br_netfilter
sudo sysctl -w net.ipv4.ip_forward=1

# init kubeadm
sudo systemctl restart containerd
sudo kubeadm init

# set config
mkdir -p $HOME/.kube
rm -rf $HOME/.kube/config
sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Set calico
rm -rf calico.yaml
curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml -O
kubectl apply -f calico.yaml

wget https://github.com/kubeedge/kubeedge/releases/download/v1.15.0/keadm-v1.15.0-linux-amd64.tar.gz
tar -zxvf keadm-v1.15.0-linux-amd64.tar.gz
cp keadm-v1.15.0-linux-amd64/keadm/keadm /usr/local/bin/keadm

kubectl apply -f yaml/device

sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

# install golang
rm -rf go1.21.1.linux-amd64.tar.gz
wget https://go.dev/dl/go1.21.1.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.21.1.linux-amd64.tar.gz
chmod +x /usr/local/go/bin
export PATH=$PATH:/usr/local/go/bin

#install kind
# For AMD64 / x86_64
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
# For ARM64
[ $(uname -m) = aarch64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-arm64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

sudo apt install iptables openssl git make manpages-dev build-essential jq -y

kubectl taint nodes --all node-role.kubernetes.io/control-plane-

rm -rf kubeedge
git clone https://github.com/kubeedge/kubeedge.git kubeedge -b release-1.14
cd kubeedge/hack
for i in $(ls update*.sh); do
  bash $i
done
for i in $(ls verify*.sh); do
  bash $i
done

cd ../..

keadm init --advertise-address="$LOCAL_IP_ADDRESS" --profile version=v1.13.0 --kube-config=/root/.kube/config

git clone https://github.com/kubeedge/edgemesh.git
#cat build/agent/resources/04-configmap.yaml
value="$(openssl rand -base64 32)"
sed -i "s/psk: JugH9HP1XBouyO5pWGeZa8LtipDURrf17EJvUHcJGuQ=/psk: ${value}/g" edgemesh/build/agent/resources/04-configmap.yaml
#nano build/agent/resources/04-configmap.yaml
kubectl apply -f edgemesh/build/crds/istio/
kubectl apply -f edgemesh/build/agent/resources/

keadm gettoken