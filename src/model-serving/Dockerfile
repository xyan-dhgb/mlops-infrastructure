FROM python:3.10-slim

# Avoiding prompt interactive when installing apt packages
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /app

# Installing system dependencies required for Pillow and TensorFlow
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libgl1-mesa-glx \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies first (leverage Docker layer cache)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy predictor source code
COPY serving.py .

# KServe default port
EXPOSE 8080

# KServe will override this CMD, but keep for local testing
CMD ["python", "serving.py", "--model_name=skin-prediction"]