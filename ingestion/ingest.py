#!/usr/bin/env python3
"""
GDrive → Qdrant ingestion pipeline
Reads from: /data/gdrive-sync (shared volume with rclone)
Writes to: Qdrant collection 'gdrive_documents'
Embeds via: LiteLLM /v1/embeddings endpoint
State tracking: /data/ingestion-state/processed_files.json (hash-based dedup)
"""

import os
import hashlib
import json
import time
import logging
from pathlib import Path
from typing import Dict, List, Optional

import requests
from qdrant_client import QdrantClient
from qdrant_client.models import PointStruct, VectorParams, Distance
import tiktoken
import watchdog.observers
from watchdog.events import FileSystemEventHandler

# Configuration
SUPPORTED_EXTENSIONS = ['.pdf', '.docx', '.txt', '.md', '.csv']
CHUNK_SIZE = 512          # tokens
CHUNK_OVERLAP = 50        # tokens  
VECTOR_DIMENSIONS = 1536  # match text-embedding-3-small
COLLECTION_NAME = "gdrive_documents"
BATCH_SIZE = 100          # upsert batch size to Qdrant
STATE_FILE = "/data/ingestion-state/processed_files.json"

# Environment variables
QDRANT_URL = os.getenv("QDRANT_URL", "http://qdrant:6333")
LITELLM_URL = os.getenv("LITELLM_URL", "http://litellm:4000")
LITELLM_MASTER_KEY = os.getenv("LITELLM_MASTER_KEY")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "text-embedding-3-small")
SYNC_DIR = os.getenv("SYNC_DIR", "/data/gdrive-sync")
WATCH_INTERVAL = int(os.getenv("WATCH_INTERVAL", "300"))  # 5 minutes

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class IngestionHandler(FileSystemEventHandler):
    """Handle file system events for new/modified files"""
    
    def __init__(self):
        self.processed_files = self.load_processed_files()
        
    def load_processed_files(self) -> Dict[str, str]:
        """Load hash index of already processed files"""
        try:
            if os.path.exists(STATE_FILE):
                with open(STATE_FILE, 'r') as f:
                    return json.load(f)
        except Exception as e:
            logger.warning(f"Could not load state file: {e}")
            return {}
    
    def save_processed_files(self, files_dict: Dict[str, str]):
        """Save hash index of processed files"""
        try:
            os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
            with open(STATE_FILE, 'w') as f:
                json.dump(files_dict, f, indent=2)
        except Exception as e:
            logger.error(f"Could not save state file: {e}")
    
    def get_file_hash(self, file_path: str) -> str:
        """Calculate SHA256 hash of file"""
        try:
            with open(file_path, 'rb') as f:
                return hashlib.sha256(f.read()).hexdigest()
        except Exception as e:
            logger.error(f"Could not hash {file_path}: {e}")
            return ""
    
    def should_process_file(self, file_path: str) -> bool:
        """Check if file should be processed (new or modified)"""
        file_hash = self.get_file_hash(file_path)
        stored_hash = self.processed_files.get(file_path, "")
        
        return file_hash != stored_hash
    
    def on_created(self, event):
        if not event.is_directory:
            self.process_file(event.src_path)
    
    def on_modified(self, event):
        if not event.is_directory:
            self.process_file(event.src_path)
    
    def process_file(self, file_path: str):
        """Process a single file"""
        if not any(file_path.lower().endswith(ext) for ext in SUPPORTED_EXTENSIONS):
            logger.debug(f"Skipping unsupported file: {file_path}")
            return
            
        if not self.should_process_file(file_path):
            logger.debug(f"File already processed: {file_path}")
            return
            
        logger.info(f"Processing file: {file_path}")
        
        try:
            # Read and chunk document
            text_content = self.read_document(file_path)
            if not text_content:
                logger.error(f"Could not extract text from {file_path}")
                return
            
            # Create embeddings and store in Qdrant
            self.embed_and_store(file_path, text_content)
            
            # Update processed files index
            self.processed_files[file_path] = self.get_file_hash(file_path)
            self.save_processed_files(self.processed_files)
            
        except Exception as e:
            logger.error(f"Error processing {file_path}: {e}")
    
    def read_document(self, file_path: str) -> Optional[str]:
        """Extract text from document based on file type"""
        try:
            if file_path.lower().endswith('.pdf'):
                return self.extract_pdf_text(file_path)
            elif file_path.lower().endswith('.docx'):
                return self.extract_docx_text(file_path)
            else:
                # Plain text files
                with open(file_path, 'r', encoding='utf-8') as f:
                    return f.read()
        except Exception as e:
            logger.error(f"Error reading {file_path}: {e}")
            return None
    
    def extract_pdf_text(self, file_path: str) -> Optional[str]:
        """Extract text from PDF using pypdf"""
        try:
            import pypdf
            with open(file_path, 'rb') as file:
                pdf_reader = pypdf.PdfReader(file)
                text = ""
                for page in pdf_reader.pages:
                    text += page.extract_text() + "\n"
                return text
        except Exception as e:
            logger.error(f"Error extracting PDF {file_path}: {e}")
            return None
    
    def extract_docx_text(self, file_path: str) -> Optional[str]:
        """Extract text from DOCX using python-docx"""
        try:
            import docx
            doc = docx.Document(file_path)
            text = ""
            for paragraph in doc.paragraphs:
                text += paragraph.text + "\n"
            return text
        except Exception as e:
            logger.error(f"Error extracting DOCX {file_path}: {e}")
            return None
    
    def chunk_text(self, text: str) -> List[str]:
        """Chunk text using tiktoken for accurate token counting"""
        try:
            import tiktoken
            encoding = tiktoken.encoding_for_model(EMBEDDING_MODEL)
            tokens = encoding.encode(text)
            
            chunks = []
            for i in range(0, len(tokens), CHUNK_SIZE - CHUNK_OVERLAP):
                chunk_tokens = tokens[max(0, i - CHUNK_OVERLAP):i + CHUNK_SIZE]
                chunk_text = encoding.decode(chunk_tokens)
                chunks.append(chunk_text)
            
            return chunks
        except Exception as e:
            logger.error(f"Error chunking text: {e}")
            return [text]  # Fallback to single chunk
    
    def embed_and_store(self, file_path: str, text_content: str):
        """Create embeddings and store in Qdrant"""
        try:
            # Initialize Qdrant client
            qdrant_client = QdrantClient(url=QDRANT_URL, timeout=30)
            
            # Ensure collection exists
            try:
                qdrant_client.get_collection(COLLECTION_NAME)
            except Exception:
                qdrant_client.create_collection(
                    collection_name=COLLECTION_NAME,
                    vectors_config=VectorParams(size=VECTOR_DIMENSIONS, distance=Distance.COSINE)
                )
                logger.info(f"Created collection: {COLLECTION_NAME}")
            
            # Get embeddings from LiteLLM
            chunks = self.chunk_text(text_content)
            points = []
            
            for i, chunk in enumerate(chunks):
                # Get embedding from LiteLLM
                embedding_response = requests.post(
                    f"{LITELLM_URL}/v1/embeddings",
                    headers={
                        "Authorization": f"Bearer {LITELLM_MASTER_KEY}",
                        "Content-Type": "application/json"
                    },
                    json={
                        "model": EMBEDDING_MODEL,
                        "input": chunk
                    },
                    timeout=60
                )
                
                if embedding_response.status_code != 200:
                    logger.error(f"Embedding failed for chunk {i}: {embedding_response.text}")
                    continue
                
                embedding_data = embedding_response.json()
                if "data" not in embedding_data:
                    logger.error(f"No embedding data in response: {embedding_data}")
                    continue
                
                embedding_vector = embedding_data["data"][0]["embedding"]
                
                # Create point for Qdrant
                point = PointStruct(
                    id=f"{file_path}_{i}",
                    vector=embedding_vector,
                    payload={
                        "file_path": file_path,
                        "chunk_index": i,
                        "chunk_text": chunk,
                        "timestamp": time.time()
                    }
                )
                points.append(point)
            
            # Batch upsert to Qdrant
            if points:
                qdrant_client.upsert(
                    collection_name=COLLECTION_NAME,
                    points=points
                )
                logger.info(f"Stored {len(points)} vectors from {file_path}")
            
        except Exception as e:
            logger.error(f"Error embedding/storing {file_path}: {e}")

def scan_existing_files():
    """Initial scan of existing files"""
    logger.info("Scanning existing files...")
    
    if not os.path.exists(SYNC_DIR):
        logger.info(f"Sync directory does not exist: {SYNC_DIR}")
        return
    
    handler = IngestionHandler()
    
    for root, dirs, files in os.walk(SYNC_DIR):
        for file in files:
            file_path = os.path.join(root, file)
            if not file.startswith('.') and any(file.lower().endswith(ext) for ext in SUPPORTED_EXTENSIONS):
                handler.process_file(file_path)

def main():
    """Main ingestion loop"""
    logger.info("Starting GDrive ingestion pipeline...")
    
    # Initial scan of existing files
    scan_existing_files()
    
    # Set up file watcher for continuous monitoring
    event_handler = IngestionHandler()
    observer = watchdog.observers.Observer()
    observer.schedule(event_handler, SYNC_DIR, recursive=True)
    
    try:
        observer.start()
        logger.info(f"Watching {SYNC_DIR} for changes...")
        
        # Keep the script running
        while True:
            time.sleep(WATCH_INTERVAL)
            
    except KeyboardInterrupt:
        observer.stop()
        logger.info("Ingestion pipeline stopped")
    except Exception as e:
        logger.error(f"Error in file watcher: {e}")

if __name__ == "__main__":
    main()
