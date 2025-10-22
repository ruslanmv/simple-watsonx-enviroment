# syntax=docker/dockerfile:1
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH="/opt/venv/bin:${PATH}"

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl git \
 && rm -rf /var/lib/apt/lists/*

# Create a dedicated venv (PEP 668-safe) and upgrade pip
RUN python -m venv /opt/venv \
 && /opt/venv/bin/python -m pip install -U pip

# Install project
WORKDIR /opt/app
COPY . .
RUN pip install --no-cache-dir .

# Workspace
WORKDIR /workspace
EXPOSE 8888

# Start Jupyter Notebook (no token)
CMD ["jupyter", "notebook", "--ip=0.0.0.0", "--no-browser", "--allow-root", "--NotebookApp.token="]
