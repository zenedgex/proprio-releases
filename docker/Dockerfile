# Proprio server image. One GPU, one policy, many robots. Built by the docker workflow in this
# repository from the compiled wheel of a published release; no Proprio sources are in the image.
#
#   docker run --gpus all -p 8000:8000 -p 8080:8080 -p 9100:9100 \
#       -e PROPRIO_LICENSE="$(cat acme.license)" -e HF_TOKEN=hf_... \
#       -v proprio-cache:/root/.cache/huggingface \
#       ghcr.io/zenedgex/proprio:0.1.1 lerobot/smolvla_base --robots 16
#
# Pinned to the stack the certificates were produced with: CUDA 12.8, torch 2.11.0+cu128,
# LeRobot 0.6.1, Python 3.12. Change the pins and re-run `proprio certify` before trusting it.
ARG CUDA=12.8.1
FROM nvidia/cuda:${CUDA}-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive PIP_NO_CACHE_DIR=1 PYTHONUNBUFFERED=1 \
    OMP_NUM_THREADS=1 TOKENIZERS_PARALLELISM=false PROPRIO_HOME=/var/lib/proprio
RUN apt-get update && apt-get install -y --no-install-recommends python3.12 python3.12-venv python3-pip \
        git ffmpeg curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* && python3.12 -m venv /opt/proprio
ENV PATH=/opt/proprio/bin:$PATH

ARG TORCH=2.11.0
ARG TORCH_INDEX=https://download.pytorch.org/whl/cu128
ARG LEROBOT=0.6.1
RUN pip install --index-url ${TORCH_INDEX} torch==${TORCH} torchvision \
    && pip install "lerobot==${LEROBOT}" websockets msgpack msgpack-numpy cryptography

# The compiled wheel of the release, verified against the published checksums.
ARG VERSION=0.1.1
RUN set -e; cd /tmp \
    && curl -fsSLO https://github.com/zenedgex/proprio-releases/releases/download/v${VERSION}/SHA256SUMS \
    && WHEEL=$(grep -o "proprio-${VERSION}-cp312-cp312-[a-z0-9_]*\.whl" SHA256SUMS | head -1) \
    && curl -fsSLO https://github.com/zenedgex/proprio-releases/releases/download/v${VERSION}/${WHEEL} \
    && grep "${WHEEL}" SHA256SUMS | sha256sum -c - \
    && pip install ./${WHEEL} && rm -f ${WHEEL} SHA256SUMS && mkdir -p ${PROPRIO_HOME}

COPY docker/entrypoint.sh /usr/local/bin/proprio-entrypoint
RUN chmod +x /usr/local/bin/proprio-entrypoint
EXPOSE 8000 8080 9100
HEALTHCHECK --interval=30s --timeout=5s --start-period=300s CMD curl -fs http://localhost:9100/health || exit 1
ENTRYPOINT ["proprio-entrypoint"]
CMD ["lerobot/smolvla_base"]
