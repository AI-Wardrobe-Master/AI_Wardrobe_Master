FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git libegl1 libgl1 libglib2.0-0 libgomp1 libglvnd0 postgresql-client && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install --no-cache-dir \
    torch==2.6.0 torchvision==0.21.0 \
    --index-url https://download.pytorch.org/whl/cu124
RUN pip install --no-cache-dir \
    accelerate diffusers einops huggingface_hub omegaconf \
    pymeshlab safetensors scikit-image sentencepiece transformers xatlas

COPY . .

CMD ["python", "scripts/docker_start.py"]
