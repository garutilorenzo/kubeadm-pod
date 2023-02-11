FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends wget lsb-release hostname gnupg dirmngr curl ca-certificates
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg |  gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
RUN echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
RUN curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
RUN echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
RUN apt-get update && apt-get install -y --no-install-recommends kubeadm
RUN apt-get install -y  --no-install-recommends python3-pip && pip3 install oci-cli
RUN apt-get clean -y && apt-get autoclean -y && apt-get autoremove -y &&  rm -rf /var/lib/apt/lists/*