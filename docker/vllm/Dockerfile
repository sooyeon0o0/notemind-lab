ARG VLLM_BASE_IMAGE=vllm/vllm-openai:v0.29.0
FROM ${VLLM_BASE_IMAGE}

USER root

# vLLM 0.29.0 supports Python 3.14, but its published container defaults to
# Python 3.12. Install 3.14 and reinstall the Python package set for that ABI.
RUN add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        python3.14 \
        python3.14-dev \
        python3.14-venv \
    && rm -rf /var/lib/apt/lists/* \
    && python3.14 -m venv /opt/py314 \
    && /opt/py314/bin/python -m pip install --upgrade pip

RUN --mount=type=cache,target=/root/.cache/pip \
    /opt/py314/bin/python -m pip install \
        --extra-index-url https://flashinfer.ai/whl/ \
        "vllm==0.29.0"

ENV PATH=/opt/py314/bin:${PATH}

RUN python3 --version \
    && python3 -c "import torch, vllm; print('torch', torch.__version__, 'cuda', torch.version.cuda, 'vllm', vllm.__version__)"

# Docker Desktop/WSL2 does not expose the pinned-memory UVA path required by
# Model Runner V2. The V1 runner is the supported fallback for this host.
ENV VLLM_USE_V2_MODEL_RUNNER=0

ENTRYPOINT ["vllm", "serve"]
