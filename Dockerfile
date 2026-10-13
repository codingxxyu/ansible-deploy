FROM python:3.12-slim

ARG ANSIBLE_CORE_VERSION=2.17.6
ARG KUBERNETES_PYTHON_VERSION=31.0.0

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    ANSIBLE_NOCOLOR=false \
    ANSIBLE_CONFIG=/opt/ansible/ansible.cfg

RUN python -m pip install --no-cache-dir \
      "ansible-core==${ANSIBLE_CORE_VERSION}" \
      "kubernetes==${KUBERNETES_PYTHON_VERSION}" \
      "PyYAML==6.0.2" \
      "jsonpatch==1.33"

COPY requirements.yml /tmp/requirements.yml
RUN ansible-galaxy collection install -r /tmp/requirements.yml

COPY ansible.cfg /opt/ansible/ansible.cfg
COPY deployment /opt/deploy-package
COPY run-deploy /usr/local/bin/run-deploy
RUN chmod 0755 /usr/local/bin/run-deploy

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/run-deploy"]
