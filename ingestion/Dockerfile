# GDrive → Qdrant Ingestion Pipeline
# Reads from: /data/gdrive-sync (shared volume with rclone)
# Writes to: Qdrant collection 'gdrive_documents'
# Embeds via: LiteLLM /v1/embeddings endpoint
# State tracking: /data/ingestion-state/processed_files.json (hash-based dedup)

FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Create ingestion state directory
RUN mkdir -p /data/ingestion-state

# Copy ingestion script
COPY ingest.py .

# Set permissions
RUN chmod +x ingest.py

# Environment variables will be passed from docker-compose.yml
CMD ["python", "ingest.py"]
