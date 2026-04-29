FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 libglib2.0-0 git curl && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install --no-cache-dir \
    https://huggingface.co/nunchaku-tech/nunchaku/resolve/main/nunchaku-0.3.2%2Btorch2.6-cp311-cp311-linux_x86_64.whl
RUN python - <<'PY'
from pathlib import Path

path = Path("/usr/local/lib/python3.11/site-packages/nunchaku/lora/flux/nunchaku_converter.py")
text = path.read_text()
old = """            fc1_v = extra_lora_dict[fc1_k]
            fc2_v = extra_lora_dict[fc2_k]
"""
new = """            if fc1_k not in extra_lora_dict or fc2_k not in extra_lora_dict:
                continue
            fc1_v = extra_lora_dict[fc1_k]
            fc2_v = extra_lora_dict[fc2_k]
"""
if old not in text:
    raise SystemExit("nunchaku converter patch target not found")
text = text.replace(old, new, 1)
old = """        extra_lora_dict.pop(f"{candidate_block_name}.proj_out.lora_A.weight")
        extra_lora_dict.pop(f"{candidate_block_name}.proj_out.lora_B.weight")
"""
new = """        extra_lora_dict.pop(f"{candidate_block_name}.proj_out.lora_A.weight")
        extra_lora_dict.pop(f"{candidate_block_name}.proj_out.lora_B.weight")
        if f"{candidate_block_name}.proj_mlp.lora_A.weight" not in extra_lora_dict:
            extra_lora_dict.pop(f"{candidate_block_name}.proj_out.linears.1.lora_A.weight", None)
            extra_lora_dict.pop(f"{candidate_block_name}.proj_out.linears.1.lora_B.weight", None)
"""
if old not in text:
    raise SystemExit("nunchaku converter split patch target not found")
path.write_text(text.replace(old, new, 1))
PY

COPY . .

EXPOSE 9000

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "9000"]
