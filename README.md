# ACP Ansible 部署

在 `global-master01` 上用 nerdctl 起 Runner 容器，进容器跑 Playbook，把 nginx 发到 ACP。

```text
/home/itopr/ansible/secure/
├── kubeconf-global.yaml
├── kubeconf-dcs-workloadcluster.yaml
├── acp-ansible-runner-amd64-0.1.0.tar
└── acp-ansible-deployer/
```

| 项 | 值 |
|---|---|
| Project | `ansible` |
| 业务集群 | `dcs-workloadcluster` |
| Namespace | `ansible-demo` |
| 应用 | `nginx` |
| 镜像 | `10.243.166.6:30020/container/nginx:latest` |
| 端口 | `80` |

当前客户机上的 runner 镜像已经构建好，**不要走镜像入口**。用 `--entrypoint /bin/sh` 起容器，部署时跑挂载进来的 Playbook。

---

## 1. 导入镜像（做过就跳过）

```bash
nerdctl --namespace default load \
  -i /home/itopr/ansible/secure/acp-ansible-runner-amd64-0.1.0.tar
```

---

## 2. 启动容器

同名容器如果还在，先删：

```bash
nerdctl --namespace default rm -f acp-ansible-runner
```

```bash
nerdctl --namespace default run -d \
  --name acp-ansible-runner \
  --platform linux/amd64 \
  --net host \
  --entrypoint /bin/sh \
  -v "/home/itopr/ansible/secure/acp-ansible-deployer:/work/project:ro" \
  -v "/home/itopr/ansible/secure/kubeconf-dcs-workloadcluster.yaml:/run/secrets/workload-kubeconfig:ro" \
  -v "/home/itopr/ansible/secure/kubeconf-global.yaml:/run/secrets/global-kubeconfig:ro" \
  -e KUBECONFIG=/run/secrets/workload-kubeconfig \
  -e ACP_GLOBAL_KUBECONFIG=/run/secrets/global-kubeconfig \
  -e ACP_KUBE_CONTEXT=proxy-connect \
  -e ACP_GLOBAL_KUBE_CONTEXT=proxy-connect \
  -e ACP_VALIDATE_CERTS=false \
  -e DEPLOY_PACKAGE=/work/project/deployment \
  acp-ansible-runner:amd64-0.1.0 \
  -c "sleep infinity"
```

`--entrypoint /bin/sh` 和最后的 `-c "sleep infinity"` 都要带，容器才会挂住。

---

## 3. 登录容器

```bash
nerdctl --namespace default exec -it acp-ansible-runner /bin/sh
```

---

## 4. 容器里部署

```bash
ansible-playbook \
  -i localhost, \
  -c local \
  /work/project/deployment/playbooks/deploy.yml
```

更新再跑同一条。退出容器：`exit`。

---

## 5. 确认 / 清理

容器外：

```bash
kubectl --kubeconfig=/home/itopr/ansible/secure/kubeconf-dcs-workloadcluster.yaml \
  --context=proxy-connect \
  -n ansible-demo get deploy,svc,pod
```

删 Runner 容器：

```bash
nerdctl --namespace default rm -f acp-ansible-runner
```

删 ACP 资源：

```bash
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
