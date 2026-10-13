# ACP Ansible 应用部署项目

本项目用于通过 Ansible 将应用发布到 ACP。项目目录和 Ansible Runner 镜像分开管理：

- 本项目目录：Playbook、配置文件和部署文档；
- Ansible Runner 镜像：Ansible、Python Kubernetes Client 和 `kubernetes.core` Collection；
- 客户 kubeconfig：客户环境的访问凭据，单独提供，不放入本项目。

## 1. 当前部署配置

默认配置文件：

```text
deployment/config/customer.example.yaml
```

当前默认部署对象：

| 配置项 | 默认值 |
|---|---|
| Global 项目 | `ansible` |
| 业务集群 | `prod-cn-north` |
| 业务 Namespace | `ansible-demo` |
| 应用名称 | `consumer` |
| 应用镜像 | `harbor.at-servicecenter.com/workshop/consumer:v1` |
| 副本数 | `1` |
| 容器端口 | `8080` |
| Service 端口 | `8080` |

Playbook 会完成：

```text
创建/确认 Project ansible
    ↓
等待 Project Active
    ↓
创建/确认 Namespace ansible-demo
    ↓
创建/更新 consumer Deployment
    ↓
创建/更新 consumer Service
    ↓
等待应用 Ready
```

Global kubeconfig 只用于 Project 管理；业务集群 kubeconfig 用于 Namespace 和应用资源管理。

## 2. 目录结构

```text
acp-ansible-deployer/
├── README.md
├── Dockerfile
├── ansible.cfg
├── requirements.yml
├── .gitignore
├── .dockerignore
└── deployment/
    ├── config/
    │   └── customer.example.yaml
    └── playbooks/
        └── deploy.yml
```

## 3. 客户环境需要准备什么

### 3.1 容器运行环境

客户执行节点需要安装以下任一方式：

- Docker；
- containerd + nerdctl。

客户是 x86 环境时，使用：

```text
linux/amd64
```

### 3.2 ACP kubeconfig

客户需要准备两个 kubeconfig：

```text
Global 管理集群 kubeconfig
业务集群 prod-cn-north kubeconfig
```

建议存放在客户执行节点的安全目录，例如：

```text
/secure/customer/kubeconf-global.yaml
/secure/customer/kubeconf-prod-cn-north.yaml
```

设置权限：

```bash
chmod 600 /secure/customer/kubeconf-global.yaml
chmod 600 /secure/customer/kubeconf-prod-cn-north.yaml
```

kubeconfig 不要放进 Git 项目，不要放进镜像，不要放进交付压缩包。

### 3.3 ACP 镜像访问

ACP 业务节点需要能够拉取业务镜像：

```text
harbor.at-servicecenter.com/workshop/consumer:v1
```

如果客户使用其他镜像地址，需要修改项目中的配置文件，并确保 ACP 节点能够访问该镜像仓库。

## 4. Ansible Runner 镜像

### 4.1 镜像中包含什么

Ansible Runner 镜像中包含：

- `ansible-core`；
- Kubernetes Python Client；
- `kubernetes.core` Collection；
- Ansible 配置；
- 一份默认部署目录 `/opt/deploy-package`。

镜像不包含：

- 客户 kubeconfig；
- Bearer Token；
- Registry 密码；
- 客户私有配置；
- 业务应用运行数据。

当前交付镜像示例：

```text
acp-ansible-runner:amd64-0.1.0
```

### 4.2 什么情况下需要修改镜像

通常不需要修改镜像。以下内容应该优先放在项目目录中修改：

| 需求 | 修改位置 |
|---|---|
| 修改应用镜像 | `deployment/config/customer.yaml` |
| 修改应用名称 | `deployment/config/customer.yaml` |
| 修改副本数 | `deployment/config/customer.yaml` |
| 修改端口 | `deployment/config/customer.yaml` |
| 修改 Project/Namespace 资源逻辑 | `deployment/playbooks/deploy.yml` |
| 修改 Ansible 依赖 | `requirements.yml` 和 `Dockerfile` |
| 修改 Ansible 配置 | `ansible.cfg` |

只有以下情况才需要重新构建 Runner 镜像：

- 修改了 `Dockerfile`；
- 修改了 `requirements.yml`；
- 修改了 `ansible.cfg`；
- 需要升级 Ansible、Python Kubernetes Client 或 Collection；
- 需要将新的工具预装进容器；
- 需要将新的非敏感文件内置进镜像。

不要因为修改了 `deployment/` 下的 Playbook 或配置就重新构建镜像。客户运行时会将项目目录挂载到容器内，使用挂载的最新内容。

### 4.3 构建 x86 Runner 镜像

在有 Docker Buildx 的环境构建：

```bash
docker buildx build \
  --platform linux/amd64 \
  --load \
  -t acp-ansible-runner:amd64-0.1.0 \
  .
```

导出镜像：

```bash
docker save \
  acp-ansible-runner:amd64-0.1.0 \
  -o acp-ansible-runner-amd64-0.1.0.tar
```

客户使用 Docker 导入：

```bash
docker load -i acp-ansible-runner-amd64-0.1.0.tar
```

客户使用 nerdctl 导入：

```bash
nerdctl --namespace default load \
  -i acp-ansible-runner-amd64-0.1.0.tar
```

## 5. 客户配置文件怎么准备和放置

### 5.1 使用默认配置

直接使用项目中的：

```text
deployment/config/customer.example.yaml
```

不需要复制到容器内部，项目目录挂载后容器可以直接读取。

### 5.2 使用客户自己的配置

不要直接修改 Git 中的示例文件。建议复制一份客户配置：

```bash
cp \
  deployment/config/customer.example.yaml \
  deployment/config/customer.yaml
```

然后只修改非敏感参数，例如：

```yaml
project_name: ansible
namespace: ansible-demo
application_name: consumer
image: harbor.at-servicecenter.com/workshop/consumer:v1
replicas: 1
container_port: 8080
service_port: 8080
image_pull_policy: IfNotPresent
```

客户配置文件建议放在项目目录外，例如：

```text
/secure/customer/acp-ansible-config/customer.yaml
```

这样可以避免把客户环境配置提交到 Git。

### 5.3 在容器内使用客户配置

启动容器时增加只读挂载：

```bash
-v "/secure/customer/acp-ansible-config/customer.yaml:/run/config/customer.yaml:ro"
```

同时增加环境变量：

```bash
-e DEPLOY_CONFIG=/run/config/customer.yaml
```

容器内执行 Ansible 时使用：

```bash
ansible-playbook \
  -i localhost, \
  -c local \
  /work/project/deployment/playbooks/deploy.yml
```

Playbook 会从 `DEPLOY_CONFIG` 指定的路径读取客户配置。

## 6. Docker 执行方式

假设客户环境中存在：

```text
Ansible Runner 镜像:
  acp-ansible-runner:amd64-0.1.0

项目目录:
  /opt/acp-ansible-deployer

Global kubeconfig:
  /secure/customer/kubeconf-global.yaml

业务 kubeconfig:
  /secure/customer/kubeconf-prod-cn-north.yaml
```

启动容器：

```bash
docker run --rm -it \
  --platform linux/amd64 \
  --network host \
  -v "/opt/acp-ansible-deployer:/work/project:ro" \
  -v "/secure/customer/kubeconf-prod-cn-north.yaml:/run/secrets/workload-kubeconfig:ro" \
  -v "/secure/customer/kubeconf-global.yaml:/run/secrets/global-kubeconfig:ro" \
  -e KUBECONFIG=/run/secrets/workload-kubeconfig \
  -e ACP_GLOBAL_KUBECONFIG=/run/secrets/global-kubeconfig \
  -e ACP_KUBE_CONTEXT=proxy-connect \
  -e ACP_GLOBAL_KUBE_CONTEXT=proxy-connect \
  -e ACP_VALIDATE_CERTS=true \
  --entrypoint /bin/sh \
  acp-ansible-runner:amd64-0.1.0
```

进入容器后执行：

```bash
ansible-playbook \
  -i localhost, \
  -c local \
  /work/project/deployment/playbooks/deploy.yml
```

## 7. containerd + nerdctl 执行方式

```bash
nerdctl --namespace default run --rm -it \
  --platform linux/amd64 \
  --net host \
  -v "/opt/acp-ansible-deployer:/work/project:ro" \
  -v "/secure/customer/kubeconf-prod-cn-north.yaml:/run/secrets/workload-kubeconfig:ro" \
  -v "/secure/customer/kubeconf-global.yaml:/run/secrets/global-kubeconfig:ro" \
  -e KUBECONFIG=/run/secrets/workload-kubeconfig \
  -e ACP_GLOBAL_KUBECONFIG=/run/secrets/global-kubeconfig \
  -e ACP_KUBE_CONTEXT=proxy-connect \
  -e ACP_GLOBAL_KUBE_CONTEXT=proxy-connect \
  -e ACP_VALIDATE_CERTS=true \
  --entrypoint /bin/sh \
  acp-ansible-runner:amd64-0.1.0
```

进入容器后执行：

```bash
ansible-playbook \
  -i localhost, \
  -c local \
  /work/project/deployment/playbooks/deploy.yml
```

## 8. 部署前后的资源范围

Playbook 只操作以下资源：

```text
Global:
  Project ansible

业务集群 prod-cn-north:
  Namespace ansible-demo
  Deployment consumer
  Service consumer
```

执行完成后，应用 Pod 应该处于 Running/Ready 状态。

重复执行同一条 Ansible 命令即可进行更新或重新发布；不需要创建第二套容器或第二个应用。

## 9. 从零重新部署

如果需要重新创建当前 Demo，按以下顺序清理：

```bash
KUBECONFIG=/run/secrets/workload-kubeconfig \
kubectl -n ansible-demo delete deployment consumer service consumer \
  --ignore-not-found=true \
  --wait=true

KUBECONFIG=/run/secrets/workload-kubeconfig \
kubectl delete namespace ansible-demo \
  --ignore-not-found=true \
  --wait=true

KUBECONFIG=/run/secrets/global-kubeconfig \
kubectl delete project.auth.alauda.io ansible \
  --ignore-not-found=true \
  --wait=true
```

清理后重新执行第 6 节或第 7 节的部署流程即可。
