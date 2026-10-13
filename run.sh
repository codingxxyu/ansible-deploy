#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
secure_dir="$(cd "$project_dir/.." && pwd)"
image="${IMAGE:-acp-ansible-runner:amd64-0.1.0}"
image_tar="${IMAGE_TAR:-$secure_dir/acp-ansible-runner-amd64-0.1.0.tar}"
workload_kubeconfig="${WORKLOAD_KUBECONFIG:-$secure_dir/kubeconf-dcs-workloadcluster.yaml}"
global_kubeconfig="${GLOBAL_KUBECONFIG:-$secure_dir/kubeconf-global.yaml}"
nerdctl_ns="${NERDCTL_NAMESPACE:-default}"
container_name="${CONTAINER_NAME:-acp-ansible-runner}"

nerdctl_cmd=(nerdctl --namespace "$nerdctl_ns")

usage() {
  cat <<EOF
Usage:
  ./run.sh load      Import $image from the tar next to this project
  ./run.sh deploy    Run the playbook once and exit
  ./run.sh shell     Enter the runner container
  ./run.sh rm        Remove a leftover runner container

Expected layout:

  $secure_dir/
  ├── kubeconf-global.yaml
  ├── kubeconf-dcs-workloadcluster.yaml
  ├── acp-ansible-runner-amd64-0.1.0.tar
  └── acp-ansible-deployer/          (this directory)
EOF
}

need_file() {
  if [[ ! -f "$1" ]]; then
    echo "missing file: $1" >&2
    exit 2
  fi
}

common_run_args() {
  need_file "$workload_kubeconfig"
  need_file "$global_kubeconfig"
  if [[ ! -d "$project_dir/deployment" ]]; then
    echo "deployment directory not found: $project_dir/deployment" >&2
    exit 2
  fi

  run_args=(
    --name "$container_name"
    --platform linux/amd64
    --net host
    -v "$project_dir:/work/project:ro"
    -v "$workload_kubeconfig:/run/secrets/workload-kubeconfig:ro"
    -v "$global_kubeconfig:/run/secrets/global-kubeconfig:ro"
    -e KUBECONFIG=/run/secrets/workload-kubeconfig
    -e ACP_GLOBAL_KUBECONFIG=/run/secrets/global-kubeconfig
    -e ACP_KUBE_CONTEXT="${ACP_KUBE_CONTEXT:-proxy-connect}"
    -e ACP_GLOBAL_KUBE_CONTEXT="${ACP_GLOBAL_KUBE_CONTEXT:-proxy-connect}"
    -e ACP_VALIDATE_CERTS="${ACP_VALIDATE_CERTS:-false}"
  )
  if [[ -n "${ACP_WORKLOAD_CLUSTER:-}" ]]; then
    run_args+=(-e "ACP_WORKLOAD_CLUSTER=$ACP_WORKLOAD_CLUSTER")
  fi
}

cmd="${1:-}"
case "$cmd" in
  load)
    need_file "$image_tar"
    "${nerdctl_cmd[@]}" load -i "$image_tar"
    "${nerdctl_cmd[@]}" images | grep acp-ansible-runner || true
    ;;
  deploy)
    common_run_args
    "${nerdctl_cmd[@]}" rm -f "$container_name" >/dev/null 2>&1 || true
    "${nerdctl_cmd[@]}" run --rm "${run_args[@]}" "$image" deploy
    ;;
  shell)
    common_run_args
    "${nerdctl_cmd[@]}" rm -f "$container_name" >/dev/null 2>&1 || true
    "${nerdctl_cmd[@]}" run --rm -it "${run_args[@]}" "$image" shell
    ;;
  rm)
    "${nerdctl_cmd[@]}" rm -f "$container_name"
    ;;
  help|-h|--help|"")
    usage
    ;;
  *)
    echo "unknown command: $cmd" >&2
    usage
    exit 2
    ;;
esac
