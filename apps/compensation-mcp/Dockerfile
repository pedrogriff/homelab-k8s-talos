# ==============================================================================
# Multi-Stage Production Dockerfile for Compensation FastMCP Microservice
# ==============================================================================

# --- Stage 1: Build & Dependencies ---
FROM python:3.13-slim AS builder

WORKDIR /build

# Install build tools
RUN apt-get update && apt-get install -y --no-install-recommends gcc && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# --- Stage 2: Minimal Distroless/Non-Root Runtime ---
FROM python:3.13-slim AS runner

WORKDIR /app

# Create unprivileged non-root user (UID 10001)
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /sbin/nologin -m appuser

# Copy installed Python packages from builder
COPY --from=builder /root/.local /home/appuser/.local
ENV PATH=/home/appuser/.local/bin:$PATH
ENV PYTHONUNBUFFERED=1

# Copy application source code with correct ownership
COPY --chown=appuser:appgroup src/ /app/src/

# Switch to unprivileged user
USER 10001:10001

EXPOSE 8000

# Start Uvicorn ASGI Server
CMD ["uvicorn", "src.server:app", "--host", "0.0.0.0", "--port", "8000"]
