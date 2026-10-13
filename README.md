# ACP Ansible 应用部署项目

在客户执行节点 `global-master01` 上，用 Ansible Runner 容器把 nginx 发布到 ACP。

客户机当前约定：

```text
执行节点: global-master01
工作目录: /home/itopr/ansible/secure
```

```text
/home/itopr/ansible/secure/
├── kubeconf-global.yaml                  # 已有，Global 集群
├── kubeconf-dcs-workloadcluster.yaml     # 已有，业务集群
├── acp-ansible-deployer/                 # 本项目，放到这里
│   ├── deployment/
│   ├── README.md
│   └── ...
└── acp-ansible-runner-amd64-0.1.0.tar    # 本机 save 后传到这里
```

kubeconfig 已经在这个目录里，不要再拷一份，也不要打进镜像。

```text
本机构建 acp-ansible-runner:amd64-0.1.0
        │
        │ docker save → tar
        ▼
/home/itopr/ansible/secure/
  nerdctl load / docker load
        │
        │ 挂载：本项目 + 两份 kubeconfig
        ▼
Ansible Runner 容器
  run-deploy deploy
        │
        ├─ kubeconf-global.yaml               → Project ansible
        └─ kubeconf-dcs-workloadcluster.yaml  → Namespace / Deployment / Service
```

---

## 1. 会部署什么

配置文件：`deployment/config/customer.example.yaml`

| 配置项 | 值 |
|---|---|
| Global 项目 | `ansible` |
| 业务集群 | `prod-cn-north` |
| 业务 Namespace | `ansible-demo` |
| 应用名称 | `nginx` |
| 应用镜像 | `10.243.166.6:30020/container/nginx:latest` |
| 副本数 | `1` |
| 容器端口 | `80` |
| Service 端口 | `80` |
| 镜像拉取 | `Always`（tag 是 `latest`） |

Playbook 顺序：

```text
Global：创建/确认 Project ansible
    ↓ 等待 Project Active
业务集群：创建/确认 Namespace ansible-demo
    ↓
创建/更新 Deployment nginx
    ↓
创建/更新 Service nginx
    ↓
等待副本 Ready 后退出
```

ACP 业务节点必须能拉取 `10.243.166.6:30020/container/nginx:latest`。Runner 镜像只负责调 API，不负责把 nginx 镜像推到仓库。

---

## 2. 开发机：导出 Runner 镜像并传到客户机

在本项目目录执行。客户机是 x86，镜像必须是 `linux/amd64`。

已经构建好时直接导出：

```bash
docker save \
  acp-ansible-runner:amd64-0.1.0 \
  -o acp-ansible-runner-amd64-0.1.0.tar
```

还没构建：

```bash
docker buildx build \
  --platform linux/amd64 \
  --load \
  -t acp-ansible-runner:amd64-0.1.0 \
  .
docker save \
  acp-ansible-runner:amd64-0.1.0 \
  -o acp-ansible-runner-amd64-0.1.0.tar
```

传到客户机（kubeconfig 已经在客户机上，不要传）：

```bash
scp -r acp-ansible-deployer \
  root@global-master01:/home/itopr/ansible/secure/

scp acp-ansible-runner-amd64-0.1.0.tar \
  root@global-master01:/home/itopr/ansible/secure/
```

传到客户机后应是：

```bash
ls -l /home/itopr/ansible/secure
```

```text
acp-ansible-deployer
acp-ansible-runner-amd64-0.1.0.tar
kubeconf-dcs-workloadcluster.yaml
kubeconf-global.yaml
```

```bash
chmod 600 \
  /home/itopr/ansible/secure/kubeconf-global.yaml \
  /home/itopr/ansible/secure/kubeconf-dcs-workloadcluster.yaml
```

---

## 3. 客户机：containerd + nerdctl（推荐）

`global-master01` 一般是 ACP 节点，用这条。容器走 `default` namespace，不要用 `k8s.io`。

### 3.1 确认环境

```bash
sudo systemctl start containerd
sudo systemctl enable containerd
systemctl is-active containerd
nerdctl version
```

### 3.2 导入 Runner 镜像

```bash
nerdctl --namespace default load \
  -i /home/itopr/ansible/secure/acp-ansible-runner-amd64-0.1.0.tar
nerdctl --namespace default images | grep acp-ansible-runner
```

应能看到 `acp-ansible-runner:amd64-0.1.0`。

### 3.3 启动并进入容器

```bash
nerdctl --namespace default run --rm -it \
  --name acp-ansible-runner \
  --platform linux/amd64 \
  --net host \
  -v "/home/itopr/ansible/secure/acp-ansible-deployer:/work/project:ro" \
  -v "/home/itopr/ansible/secure/kubeconf-dcs-workloadcluster.yaml:/run/secrets/workload-kubeconfig:ro" \
  -v "/home/itopr/ansible/secure/kubeconf-global.yaml:/run/secrets/global-kubeconfig:ro" \
  -e KUBECONFIG=/run/secrets/workload-kubeconfig \
  -e ACP_GLOBAL_KUBECONFIG=/run/secrets/global-kubeconfig \
  -e ACP_KUBE_CONTEXT=proxy-connect \
  -e ACP_GLOBAL_KUBE_CONTEXT=proxy-connect \
  -e ACP_VALIDATE_CERTS=true \
  acp-ansible-runner:amd64-0.1.0 \
  shell
```

### 3.4 容器里执行部署

```bash
ls -l /work/project/deployment/playbooks/deploy.yml
ls -l /run/secrets/workload-kubeconfig
ls -l /run/secrets/global-kubeconfig
```

```bash
run-deploy deploy
```

或：

```bash
ansible-playbook \
  -i localhost, \
  -c local \
  /work/project/deployment/playbooks/deploy.yml
```

项目已经挂到 `/work/project`，不必再设 `DEPLOY_PACKAGE`。成功时会打印 `application: nginx` 和 `ready_replicas: 1`，然后退出。

### 3.5 不进交互 shell，一条命令跑完

```bash
nerdctl --namespace default run --rm \
  --name acp-ansible-runner \
  --platform linux/amd64 \
  --net host \
  -v "/home/itopr/ansible/secure/acp-ansible-deployer:/work/project:ro" \
  -v "/home/itopr/ansible/secure/kubeconf-dcs-workloadcluster.yaml:/run/secrets/workload-kubeconfig:ro" \
  -v "/home/itopr/ansible/secure/kubeconf-global.yaml:/run/secrets/global-kubeconfig:ro" \
  -e KUBECONFIG=/run/secrets/workload-kubeconfig \
  -e ACP_GLOBAL_KUBECONFIG=/run/secrets/global-kubeconfig \
  -e ACP_KUBE_CONTEXT=proxy-connect \
  -e ACP_GLOBAL_KUBE_CONTEXT=proxy-connect \
  -e ACP_VALIDATE_CERTS=true \
  acp-ansible-runner:amd64-0.1.0 \
  deploy
```

---

## 4. 客户机：Docker

客户机装的是 Docker 时用这一节，路径和挂载与上一节相同。

### 4.1 确认 Docker 并导入镜像

```bash
sudo systemctl start docker
sudo systemctl enable docker
docker info

docker load -i /home/itopr/ansible/secure/acp-ansible-runner-amd64-0.1.0.tar
docker images | grep acp-ansible-runner
```

### 4.2 启动并进入容器

```bash
docker run --rm -it \
  --name acp-ansible-runner \
  --platform linux/amd64 \
  --network host \
  -v "/home/itopr/ansible/secure/acp-ansible-deployer:/work/project:ro" \
  -v "/home/itopr/ansible/secure/kubeconf-dcs-workloadcluster.yaml:/run/secrets/workload-kubeconfig:ro" \
  -v "/home/itopr/ansible/secure/kubeconf-global.yaml:/run/secrets/global-kubeconfig:ro" \
  -e KUBECONFIG=/run/secrets/workload-kubeconfig \
  -e ACP_GLOBAL_KUBECONFIG=/run/secrets/global-kubeconfig \
  -e ACP_KUBE_CONTEXT=proxy-connect \
  -e ACP_GLOBAL_KUBE_CONTEXT=proxy-connect \
  -e ACP_VALIDATE_CERTS=true \
  acp-ansible-runner:amd64-0.1.0 \
  shell
```

进容器后同样执行：

```bash
run-deploy deploy
```

### 4.3 一条命令跑完

```bash
docker run --rm \
  --name acp-ansible-runner \
  --platform linux/amd64 \
  --network host \
  -v "/home/itopr/ansible/secure/acp-ansible-deployer:/work/project:ro" \
  -v "/home/itopr/ansible/secure/kubeconf-dcs-workloadcluster.yaml:/run/secrets/workload-kubeconfig:ro" \
  -v "/home/itopr/ansible/secure/kubeconf-global.yaml:/run/secrets/global-kubeconfig:ro" \
  -e KUBECONFIG=/run/secrets/workload-kubeconfig \
  -e ACP_GLOBAL_KUBECONFIG=/run/secrets/global-kubeconfig \
  -e ACP_KUBE_CONTEXT=proxy-connect \
  -e ACP_GLOBAL_KUBE_CONTEXT=proxy-connect \
  -e ACP_VALIDATE_CERTS=true \
  acp-ansible-runner:amd64-0.1.0 \
  deploy
```

---

## 5. 想留着容器反复进

去掉 `--rm`，让容器挂着。nerdctl：

```bash
nerdctl --namespace default run -d \
  --name acp-ansible-runner \
  --platform linux/amd64 \
  --net host \
  -v "/home/itopr/ansible/secure/acp-ansible-deployer:/work/project:ro" \
  -v "/home/itopr/ansible/secure/kubeconf-dcs-workloadcluster.yaml:/run/secrets/workload-kubeconfig:ro" \
  -v "/home/itopr/ansible/secure/kubeconf-global.yaml:/run/secrets/global-kubeconfig:ro" \
  -e KUBECONFIG=/run/secrets/workload-kubeconfig \
  -e ACP_GLOBAL_KUBECONFIG=/run/secrets/global-kubeconfig \
  -e ACP_KUBE_CONTEXT=proxy-connect \
  -e ACP_GLOBAL_KUBE_CONTEXT=proxy-connect \
  -e ACP_VALIDATE_CERTS=true \
  acp-ansible-runner:amd64-0.1.0 \
  sleep infinity
```

再进去：

```bash
nerdctl --namespace default exec -it acp-ansible-runner /bin/sh
```

Docker：

```bash
docker run -d \
  --name acp-ansible-runner \
  --platform linux/amd64 \
  --network host \
  -v "/home/itopr/ansible/secure/acp-ansible-deployer:/work/project:ro" \
  -v "/home/itopr/ansible/secure/kubeconf-dcs-workloadcluster.yaml:/run/secrets/workload-kubeconfig:ro" \
  -v "/home/itopr/ansible/secure/kubeconf-global.yaml:/run/secrets/global-kubeconfig:ro" \
  -e KUBECONFIG=/run/secrets/workload-kubeconfig \
  -e ACP_GLOBAL_KUBECONFIG=/run/secrets/global-kubeconfig \
  -e ACP_KUBE_CONTEXT=proxy-connect \
  -e ACP_GLOBAL_KUBE_CONTEXT=proxy-connect \
  -e ACP_VALIDATE_CERTS=true \
  acp-ansible-runner:amd64-0.1.0 \
  sleep infinity
```

```bash
docker exec -it acp-ansible-runner /bin/sh
```

进去后执行 `run-deploy deploy`。

如果 nerdctl 不接受把 `sleep infinity` 当镜像后的命令，改成：

```bash
nerdctl --namespace default run -d \
  --name acp-ansible-runner \
  --platform linux/amd64 \
  --net host \
  --entrypoint sleep \
  -v "/home/itopr/ansible/secure/acp-ansible-deployer:/work/project:ro" \
  -v "/home/itopr/ansible/secure/kubeconf-dcs-workloadcluster.yaml:/run/secrets/workload-kubeconfig:ro" \
  -v "/home/itopr/ansible/secure/kubeconf-global.yaml:/run/secrets/global-kubeconfig:ro" \
  -e KUBECONFIG=/run/secrets/workload-kubeconfig \
  -e ACP_GLOBAL_KUBECONFIG=/run/secrets/global-kubeconfig \
  -e ACP_KUBE_CONTEXT=proxy-connect \
  -e ACP_GLOBAL_KUBE_CONTEXT=proxy-connect \
  -e ACP_VALIDATE_CERTS=true \
  acp-ansible-runner:amd64-0.1.0 \
  infinity
```

---

## 6. 怎么确认部署成功

Playbook 正常结束，且打印了 `ready_replicas: 1`，就表示 Deployment 已经 Ready。

Runner 镜像没有 `kubectl`。在客户机容器外验证：

```bash
kubectl --kubeconfig=/home/itopr/ansible/secure/kubeconf-dcs-workloadcluster.yaml \
  --context=proxy-connect \
  -n ansible-demo get deploy,svc,pod
```

应能看到 Deployment `nginx`、Service `nginx`，以及 1 个 Running/Ready 的 Pod。

kubeconfig 的 context 不是 `proxy-connect` 时，先查：

```bash
kubectl --kubeconfig=/home/itopr/ansible/secure/kubeconf-dcs-workloadcluster.yaml config get-contexts
kubectl --kubeconfig=/home/itopr/ansible/secure/kubeconf-global.yaml config get-contexts
```

然后改启动命令里的 `ACP_KUBE_CONTEXT` 和 `ACP_GLOBAL_KUBE_CONTEXT`。

---

## 7. 重复执行 / 更新发布

同一条 `run-deploy deploy` 再跑即可，不会建第二套应用。

- 没改配置：确认现有资源仍符合预期
- 改了镜像或副本：更新现有 Deployment，等到新副本 Ready

改业务参数只改项目里这份文件，然后重新跑 Playbook，**不用重建 Runner 镜像**：

```text
/home/itopr/ansible/secure/acp-ansible-deployer/deployment/config/customer.example.yaml
```

当前内容：

```yaml
project_name: ansible
namespace: ansible-demo
application_name: nginx
image: 10.243.166.6:30020/container/nginx:latest
replicas: 1
container_port: 80
service_port: 80
image_pull_policy: Always
```

不要把仓库密码写进这份 YAML。私有仓库认证走客户 ACP 现有的 ImagePullSecret。

---

## 8. 改什么要重建 Runner 镜像

| 你要改的 | 改哪里 | 要不要重建 |
|---|---|---|
| nginx 镜像、副本、端口、应用名 | `deployment/config/customer.example.yaml` | 否 |
| Playbook 逻辑 | `deployment/playbooks/deploy.yml` | 否，挂载项目目录即可 |
| Ansible / Collection / 镜像内工具 | `Dockerfile`、`requirements.yml`、`ansible.cfg` | **是** |

重建后再传到客户机：

```bash
docker buildx build --platform linux/amd64 --load -t acp-ansible-runner:amd64-0.1.0 .
docker save acp-ansible-runner:amd64-0.1.0 -o acp-ansible-runner-amd64-0.1.0.tar
scp acp-ansible-runner-amd64-0.1.0.tar \
  root@global-master01:/home/itopr/ansible/secure/
```

客户机重新导入前，先删旧容器：

```bash
nerdctl --namespace default rm -f acp-ansible-runner
nerdctl --namespace default load \
  -i /home/itopr/ansible/secure/acp-ansible-runner-amd64-0.1.0.tar
```

或：

```bash
docker rm -f acp-ansible-runner
docker load -i /home/itopr/ansible/secure/acp-ansible-runner-amd64-0.1.0.tar
```

---

## 9. 清理后再重新部署

### 9.1 删执行节点上的 Runner 容器

交互且带了 `--rm`：容器里 `exit` 即可。

常驻容器：

```bash
nerdctl --namespace default rm -f acp-ansible-runner
```

```bash
docker rm -f acp-ansible-runner
```

可选，连 Runner 镜像一起删（不影响 ACP 里已经发布的 nginx）：

```bash
nerdctl --namespace default rmi acp-ansible-runner:amd64-0.1.0
```

```bash
docker rmi acp-ansible-runner:amd64-0.1.0
```

### 9.2 删 ACP 里的 Demo 资源

在客户机容器外、有 kubectl 的地方执行。先删业务资源，再删 Namespace，最后用 Global kubeconfig 删 Project：

```bash
WORKLOAD_KUBECONFIG=/home/itopr/ansible/secure/kubeconf-dcs-workloadcluster.yaml
GLOBAL_KUBECONFIG=/home/itopr/ansible/secure/kubeconf-global.yaml
CTX=proxy-connect

kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" --context="$CTX" \
  -n ansible-demo delete deployment nginx service nginx \
  --ignore-not-found=true --wait=true

kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" --context="$CTX" \
  delete namespace ansible-demo \
  --ignore-not-found=true --wait=true

kubectl --kubeconfig="$GLOBAL_KUBECONFIG" --context="$CTX" \
  delete project.auth.alauda.io ansible \
  --ignore-not-found=true --wait=true
```

清理后再跑第 3.5 或第 4.3 节，就是从零重新部署。

---

## 10. 目录和查找顺序

```text
acp-ansible-deployer/
├── README.md
├── Dockerfile
├── ansible.cfg
├── requirements.yml
├── run-deploy
└── deployment/
    ├── config/customer.example.yaml
    └── playbooks/deploy.yml
```

部署目录查找顺序：

```text
1. 环境变量 DEPLOY_PACKAGE
2. /work/project/deployment          ← 按上面命令挂载后走这里
3. /opt/deploy-package               ← 镜像内置兜底
```

配置文件查找顺序：

```text
1. 环境变量 DEPLOY_CONFIG
2. $DEPLOY_PACKAGE/config/customer.yaml
3. $DEPLOY_PACKAGE/config/customer.example.yaml
```

| 变量 | 默认 | 含义 |
|---|---|---|
| `DEPLOY_PACKAGE` | 先 `/work/project/deployment`，再 `/opt/deploy-package` | Playbook 目录 |
| `DEPLOY_CONFIG` | `customer.yaml`，没有则 `customer.example.yaml` | 业务参数 |
| `KUBECONFIG` | `/run/secrets/workload-kubeconfig` | 业务集群 kubeconfig |
| `ACP_GLOBAL_KUBECONFIG` | `/run/secrets/global-kubeconfig` | Global kubeconfig |
| `ACP_KUBE_CONTEXT` | `proxy-connect` | 业务集群 context |
| `ACP_GLOBAL_KUBE_CONTEXT` | `proxy-connect` | Global context |
| `ACP_VALIDATE_CERTS` | `true` | 校验证书 |

按第 3 / 4 节挂载时不必设 `DEPLOY_PACKAGE`。
