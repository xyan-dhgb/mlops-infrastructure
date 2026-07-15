FROM python:3.10-slim

# Avoiding prompt interactive when installing apt packages
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /app

# System deps for OpenCV headless + Pillow (Debian Bookworm / python:3.10-slim)
# libgl1-mesa-glx was renamed to libgl1 in Debian Bookworm
# opencv-python-headless still needs libgl1, libglib2.0-0, libsm6, libxext6
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libgl1 \
    libsm6 \
    libxext6 \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies first (leverage Docker layer cache)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy predictor source code + font for Vietnamese XAI overlay
COPY serving.py .
COPY DejaVuSans-Bold.ttf .

# KServe default port
EXPOSE 8080

# KServe will override this CMD, but keep for local testing
CMD ["python", "serving.py", "--model_name=skin-prediction"]