# Multipass QEMU 타임아웃 문제 해결

## 근본 원인
ARM Mac에서 Multipass 1.16.1 + QEMU 조합이 VM 네트워크 초기화 중 타임아웃 발생

## 해결 방법

### 방법 1: Multipass 완전 재설치

```bash
# 1. Multipass 완전 제거
brew uninstall multipass
sudo rm -rf /Library/Application\ Support/com.canonical.multipass
sudo rm -rf ~/Library/Application\ Support/multipassd
sudo rm -rf /var/root/Library/Application\ Support/multipassd

# 2. 재설치
brew install multipass

# 3. 데몬 재시작
sudo launchctl stop com.canonical.multipass
sudo launchctl start com.canonical.multipass

# 4. 테스트
multipass launch --name test
```

### 방법 2: Colima 사용 (대안)

Multipass 대신 Colima를 사용하여 Kubernetes 클러스터 구성:

```bash
# Colima 설치
brew install colima

# Kubernetes 클러스터 시작
colima start --cpu 4 --memory 8 --disk 50 --kubernetes

# kubectl 사용
kubectl get nodes
```

### 방법 3: Kind 사용 (가장 간단)

Docker 안에서 Kubernetes 실행:

```bash
# Kind 설치
brew install kind

# 클러스터 생성
kind create cluster --name test-cluster

# kubectl 사용
kubectl cluster-info
```

### 방법 4: Minikube 사용

```bash
# Minikube 설치
brew install minikube

# 클러스터 시작
minikube start --driver=qemu --cpus 2 --memory 4096

# kubectl 사용
kubectl get nodes
```

## 추천 순서

1. **Kind** - 가장 빠르고 안정적 (단, Docker 필요)
2. **Colima** - Docker + Kubernetes 통합, ARM Mac 최적화
3. **Multipass 재설치** - 원래 방법으로 돌아가기
4. **Minikube** - 오래된 안정적 옵션

## 로컬 테스트 스크립트 수정 필요

현재 스크립트는 Multipass 전용이므로, 대안을 선택하면 스크립트 수정이 필요합니다.
