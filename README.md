# ACP Ansible 部署

在 `global-master01` 上用 **nerdctl** 起 Ansible Runner，把 nginx 发到 ACP。

```text
本机构建 runner 镜像
        ↓ docker save
客户机 /home/itopr/ansible/secure/
        ↓ nerdctl load + ./run.sh deploy
容器里跑 Playbook
        ├─ kubeconf-global.yaml              → Project
        └─ kubeconf-dcs-workloadcluster.yaml → Namespace / Deployment / Service
```

kubeconfig 已经在客户机上，不要打进镜像，也不要放进 Git。

## 部署什么

`deployment/config/customer.example.yaml`

| 项 | 值 |
|---|---|
| Project | `ansible` |
| 业务集群 | `dcs-workloadcluster` |
| Namespace | `ansible-demo` |
| 应用 | `nginx` |
| 镜像 | `10.243.166.6:30020/container/nginx:latest` |
| 端口 | `80` |

ACP 节点必须能自己拉取这个 nginx 镜像。Runner 只调 API。

## 客户机目录

```text
/home/itopr/ansible/secure/
├── kubeconf-global.yaml
├── kubeconf-dcs-workloadcluster.yaml
├── acp-ansible-runner-amd64-0.1.0.tar
└── acp-ansible-deployer/
    ├── run.sh
    ├── deployment/
    └── README.md
```

本机导出并上传（x86 客户机必须是 `linux/amd64`）：

```bash
docker buildx build --platform linux/amd64 --load -t acp-ansible-runner:amd64-0.1.0 .
docker save acp-ansible-runner:amd64-0.1.0 -o acp-ansible-runner-amd64-0.1.0.tar

scp -r acp-ansible-deployer root@global-master01:/home/itopr/ansible/secure/
scp acp-ansible-runner-amd64-0.1.0.tar root@global-master01:/home/itopr/ansible/secure/
```

## 客户机执行

containerd 用 `default` namespace，不要用 `k8s.io`。

```bash
cd /home/itopr/ansible/secure/acp-ansible-deployer
chmod +x run.sh

./run.sh load
./run.sh deploy
```

要进容器再跑：

```bash
./run.sh shell
# 容器内
run-deploy deploy
```

`run.sh` 会挂上项目目录和两份 kubeconfig，并带上这个环境已经验证过的参数：

- `ACP_VALIDATE_CERTS=false`（kubeconfig CA 对不上 `10.243.166.5:443`）
- 业务集群名读配置里的 `dcs-workloadcluster`（不是 `prod-cn-north`）

改业务参数只改 `deployment/config/customer.example.yaml`，再 `./run.sh deploy`。不用重建 runner 镜像。

## 确认

Runner 里没有 kubectl，在客户机上查：

```bash
kubectl --kubeconfig=/home/itopr/ansible/secure/kubeconf-dcs-workloadcluster.yaml \
  --context=proxy-connect \
  -n ansible-demo get deploy,svc,pod
```

## 重复执行 / 清理

同一条 `./run.sh deploy` 再跑就是更新，不会建第二套应用。

```bash
# 删 runner 容器（不影响 ACP 里的 nginx）
./run.sh rm

# 删 ACP 资源
WORKLOAD=/home/itopr/ansible/secure/kubeconf-dcs-workloadcluster.yaml
GLOBAL=/home/itopr/ansible/secure/kubeconf-global.yaml
CTX=proxy-connect

kubectl --kubeconfig="$WORKLOAD" --context="$CTX" \
  -n ansible-demo delete deploy nginx svc nginx --ignore-not-found --wait
kubectl --kubeconfig="$WORKLOAD" --context="$CTX" \
  delete ns ansible-demo --ignore-not-found --wait
kubectl --kubeconfig="$GLOBAL" --context="$CTX" \
  delete project.auth.alauda.io ansible --ignore-not-found --wait
```

## 排障

**证书错误** `unable to get local issuer certificate` / `host='10.243.166.5'`  
用 `./run.sh` 即可。人已经在容器里时：

```bash
export ACP_VALIDATE_CERTS=false
run-deploy deploy
```

**422** `cluster xxx does not exist`  
Project 绑定的业务集群名在 Global 上不存在。查真实名字：

```bash
kubectl --kubeconfig=/home/itopr/ansible/secure/kubeconf-global.yaml \
  --context=proxy-connect \
  get clusters.cluster.alauda.io
```

写进 `workload_cluster_name`，或：

```bash
ACP_WORKLOAD_CLUSTER=真实集群名 ./run.sh deploy
```

**context 不对**  

```bash
kubectl --kubeconfig=/home/itopr/ansible/secure/kubeconf-global.yaml config get-contexts
kubectl --kubeconfig=/home/itopr/ansible/secure/kubeconf-dcs-workloadcluster.yaml config get-contexts
```

```bash
ACP_KUBE_CONTEXT=xxx ACP_GLOBAL_KUBE_CONTEXT=xxx ./run.sh deploy
```
