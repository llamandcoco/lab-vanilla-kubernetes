# Vagrant + VMware Fusion을 사용한 로컬 Kubernetes 테스트

## 왜 Vagrant인가?

- Multipass 대신 Vagrant 사용
- ARM Mac에서 VMware Fusion 지원
- Ansible과 완벽 통합
- 실제 VM 환경에서 Kubernetes 설치 가능

## 설치

```bash
# 1. VMware Fusion 설치 (개인용 무료)
# https://www.vmware.com/products/fusion/fusion-evaluation.html
brew install --cask vmware-fusion

# 2. Vagrant 설치
brew install vagrant

# 3. Vagrant VMware 유틸리티 설치
brew install --cask vagrant-vmware-utility

# 4. Vagrant VMware provider 설치
vagrant plugin install vagrant-vmware-desktop
```

## Vagrantfile 예제

```ruby
Vagrant.configure("2") do |config|
  # Ubuntu 22.04 ARM64
  config.vm.box = "bento/ubuntu-22.04-arm64"

  # VMware provider
  config.vm.provider "vmware_desktop" do |v|
    v.gui = false
  end

  # Control Plane
  config.vm.define "k8s-control-plane-01" do |cp|
    cp.vm.hostname = "k8s-control-plane-01"
    cp.vm.network "private_network", type: "dhcp"

    cp.vm.provider "vmware_desktop" do |v|
      v.vmx["memsize"] = "4096"
      v.vmx["numvcpus"] = "2"
    end
  end

  # Worker Node
  config.vm.define "k8s-worker-01" do |worker|
    worker.vm.hostname = "k8s-worker-01"
    worker.vm.network "private_network", type: "dhcp"

    worker.vm.provider "vmware_desktop" do |v|
      v.vmx["memsize"] = "4096"
      v.vmx["numvcpus"] = "2"
    end
  end

  # Ansible provisioning (선택 사항)
  config.vm.provision "ansible" do |ansible|
    ansible.playbook = "../ansible/playbooks/site.yml"
    ansible.inventory_path = "inventory/hosts.yml"
  end
end
```

## 사용 방법

```bash
# VM 시작
vagrant up

# SSH 접근
vagrant ssh k8s-control-plane-01

# Ansible 실행 (Vagrant 외부에서)
ansible-playbook -i inventory/hosts.yml ../ansible/playbooks/00-prerequisites.yml

# VM 중지
vagrant halt

# VM 삭제
vagrant destroy -f
```

## Ansible Inventory 생성

Vagrant는 자동으로 inventory를 생성할 수도 있지만, 수동으로도 가능:

```bash
# Vagrant SSH 설정 확인
vagrant ssh-config

# Ansible inventory 생성
cat > inventory/hosts.yml <<EOF
all:
  children:
    control_plane:
      hosts:
        k8s-control-plane-01:
          ansible_host: $(vagrant ssh-config k8s-control-plane-01 | grep HostName | awk '{print $2}')
          ansible_port: $(vagrant ssh-config k8s-control-plane-01 | grep Port | awk '{print $2}')
          ansible_user: vagrant
          ansible_ssh_private_key_file: $(vagrant ssh-config k8s-control-plane-01 | grep IdentityFile | awk '{print $2}')
    workers:
      hosts:
        k8s-worker-01:
          ansible_host: $(vagrant ssh-config k8s-worker-01 | grep HostName | awk '{print $2}')
          ansible_port: $(vagrant ssh-config k8s-worker-01 | grep Port | awk '{print $2}')
          ansible_user: vagrant
          ansible_ssh_private_key_file: $(vagrant ssh-config k8s-worker-01 | grep IdentityFile | awk '{print $2}')
EOF
```

## 장점

- ✅ Multipass와 거의 동일한 워크플로우
- ✅ ARM Mac 완벽 지원
- ✅ Ansible 완벽 호환
- ✅ 실제 VM (완전한 systemd, Kubernetes 설치 가능)
- ✅ 안정적 (Multipass QEMU 타임아웃 문제 없음)

## 단점

- ❌ VMware Fusion 별도 설치 필요
- ❌ 초기 설정이 Multipass보다 조금 복잡
