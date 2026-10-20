# Aura by HS — Python API
#
# Render does NOT use this file. render.yaml declares `runtime: python`, which
# is Render's native build: faster, cached, and one less thing to maintain.
# This Dockerfile exists so the API can also run anywhere a container runs —
# Fly.io, Railway, Cloud Run, a VPS, or a colleague's laptop — without
# installing Python or matching versions by hand.
#
# Build and run locally:
#   docker build -t aura-api ./backend
#   docker run --rm -p 8000:8000 --env-file backend/.env aura-api
#   open http://127.0.0.1:8000/health
#
# To make Render use this instead, change render.yaml to:
#   runtime: docker
#   dockerfilePath: ./Dockerfile      (rootDir is already backend)

# 3.12 matches PYTHON_VERSION in render.yaml. -slim keeps the image small
# without the breakage that -alpine causes for packages with C extensions
# (cryptography, used for Easypaisa's AES, is one of them).
FROM python:3.12-slim

# PYTHONDONTWRITEBYTECODE  no .pyc files; the container is thrown away anyway
# PYTHONUNBUFFERED         logs appear immediately instead of being held in a
#                          buffer, which otherwise makes a crash look silent
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Dependencies are copied and installed before the source, so editing a .py
# file does not invalidate the layer and reinstall everything on every build.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Run as a non-root user. If the process is ever compromised, it should not own
# the filesystem it is standing on.
RUN useradd --create-home --uid 10001 aura && chown -R aura:aura /app
USER aura

# Documentation only — the published port is decided by `docker run -p`.
EXPOSE 8000

# PORT is injected by most hosts (Render, Cloud Run, Railway); 8000 is the
# local default. Shell form so ${PORT} is actually expanded — the exec form
# would pass the literal string "${PORT}" to uvicorn and fail to bind.
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}
