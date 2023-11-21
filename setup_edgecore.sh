LOCAL_IP_ADDRESS=192.168.107.4 #master ip
TOKEN="" #your token

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

mkdir /etc/cni

cat > /etc/cni/net.d/10-containerd-net.conflist <<EOF
{
     "cniVersion": "1.0.0",
     "name": "containerd-net",
     "plugins": [
       {
         "type": "bridge",
         "bridge": "cni0",
         "isGateway": true,
         "ipMasq": true,
         "promiscMode": true,
         "ipam": {
           "type": "host-local",
           "ranges": [
             [{
               "subnet": "10.88.0.0/16"
             }],
             [{
               "subnet": "2001:db8:4860::/64"
             }]
           ],
           "routes": [
             { "dst": "0.0.0.0/0" },
             { "dst": "::/0" }
           ]
         }
       },
       {
         "type": "portmap",
         "capabilities": {"portMappings": true}
       }
     ]
    }
EOF

sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

wget https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.28.0/crictl-v1.28.0-linux-amd64.tar.gz
tar -xvf crictl-v1.28.0-linux-amd64.tar.gz
cp crictl /usr/local/bin
crictl config runtime-endpoint unix:///run/containerd/containerd.sock
crictl config image-endpoint unix:///run/containerd/containerd.sock
rm -rf /etc/kubeedge/

sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

wget https://github.com/kubeedge/kubeedge/releases/download/v1.15.0/keadm-v1.15.0-linux-amd64.tar.gz
tar -zxvf keadm-v1.15.0-linux-amd64.tar.gz
cp keadm-v1.15.0-linux-amd64/keadm/keadm /usr/local/bin/keadm

ctr -n k8s.io c rm $(ctr -n k8s.io c ls -q)

sed -i -e "s/ExecStart=\/usr\/bin\/dockerd -H fd:\/\/ --containerd=\/run\/containerd\/containerd.sock/ExecStart=\/usr\/bin\/dockerd -H fd:\/\/ --containerd=\/run\/containerd\/containerd.sock --exec-opt native.cgroupdriver=systemd/g" /usr/lib/systemd/system/docker.service

rm -rf /etc/docker/daemon.json
mkdir -p /etc/docker
echo '{
  "exec-opts": ["native.cgroupdriver=systemd"]
}' >> /etc/docker/daemon.json

systemctl restart docker
systemctl daemon-reload
sudo systemctl restart containerd

keadm join --cloudcore-ipport=$LOCAL_IP_ADDRESS:10000 --token=$TOKEN --kubeedge-version=v1.13.0 --cgroupdriver=systemd --runtimetype=docker --remote-runtime-endpoint=unix:///var/run/containerd/containerd.sock