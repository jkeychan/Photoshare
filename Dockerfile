# Build stage: install dependencies into an isolated venv
FROM python:3.14-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN python -m venv /opt/venv \
    && . /opt/venv/bin/activate \
    && pip install --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# Production stage: lean image with venv + app source only
FROM python:3.14-slim

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy application source (no bind-mount override in production)
COPY app.py config.py thumbnailer.py ./
COPY templates/ templates/
COPY static/ static/

RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

# 2 workers suits the B2ls_v2 (2 vCPU); adjust if VM is resized.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--timeout", "120", "app:app"]
