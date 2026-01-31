#!/usr/bin/env python3
"""
ClawDBot - Signal to AnythingLLM Bridge
Receives messages from Signal REST API webhooks and forwards to AnythingLLM
"""

import json
import logging
import os
import sys
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from threading import Thread
from typing import Dict, Any, Optional

import requests

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/app/logs/clawdbot.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('ClawDBot')

# Load configuration
CONFIG_FILE = os.getenv('CONFIG_FILE', '/app/config/config.json')

try:
    with open(CONFIG_FILE, 'r') as f:
        CONFIG = json.load(f)
    logger.info(f"Configuration loaded from {CONFIG_FILE}")
except Exception as e:
    logger.error(f"Failed to load config: {e}")
    sys.exit(1)

# Configuration shortcuts
SIGNAL_API_URL = CONFIG['signal']['api_url']
SIGNAL_PHONE = CONFIG['signal']['phone_number']
ANYTHINGLLM_URL = CONFIG['anythingllm']['api_url']
ANYTHINGLLM_API_KEY = CONFIG['anythingllm']['api_key']
ANYTHINGLLM_WORKSPACE = CONFIG['anythingllm']['workspace_slug']
BOT_NAME = CONFIG['bot']['name']
PORT = CONFIG.get('port', 18789)

# State management (in-memory conversation history)
conversations: Dict[str, list] = {}


class SignalWebhookHandler(BaseHTTPRequestHandler):
    """Handle incoming Signal webhooks"""
    
    def log_message(self, format, *args):
        """Override to use our logger"""
        logger.info(f"HTTP {format % args}")
    
    def do_GET(self):
        """Health check endpoint"""
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'ClawDBot healthy')
        else:
            self.send_response(404)
            self.end_headers()
    
    def do_POST(self):
        """Handle Signal webhook POSTs"""
        if self.path != '/webhook':
            self.send_response(404)
            self.end_headers()
            return
        
        try:
            # Read request body
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode('utf-8')
            
            logger.info(f"Received webhook: {body[:200]}...")
            
            # Parse Signal message
            data = json.loads(body)
            
            # Extract message details
            envelope = data.get('envelope', {})
            source = envelope.get('source') or envelope.get('sourceNumber')
            message_text = envelope.get('dataMessage', {}).get('message', '')
            timestamp = envelope.get('timestamp', int(time.time() * 1000))
            
            if not source or not message_text:
                logger.warning("Received webhook without source or message")
                self.send_response(200)
                self.end_headers()
                return
            
            # Ignore our own messages
            if source == SIGNAL_PHONE:
                self.send_response(200)
                self.end_headers()
                return
            
            logger.info(f"Message from {source}: {message_text}")
            
            # Process message in background
            Thread(target=self.process_message, args=(source, message_text, timestamp)).start()
            
            # Immediately respond 200 to Signal API
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "received"}).encode())
            
        except Exception as e:
            logger.error(f"Error handling webhook: {e}", exc_info=True)
            self.send_response(500)
            self.end_headers()
    
    def process_message(self, sender: str, message: str, timestamp: int):
        """Process incoming message and respond"""
        try:
            # Send to AnythingLLM
            response_text = self.query_anythingllm(sender, message)
            
            if response_text:
                # Send response via Signal
                self.send_signal_message(sender, response_text)
            else:
                # Error occurred
                self.send_signal_message(sender, CONFIG['bot']['error_message'])
                
        except Exception as e:
            logger.error(f"Error processing message: {e}", exc_info=True)
            try:
                self.send_signal_message(sender, CONFIG['bot']['error_message'])
            except:
                pass
    
    def query_anythingllm(self, sender: str, message: str) -> Optional[str]:
        """Query AnythingLLM workspace"""
        try:
            url = f"{ANYTHINGLLM_URL}/api/v1/workspace/{ANYTHINGLLM_WORKSPACE}/chat"
            
            headers = {
                'Authorization': f'Bearer {ANYTHINGLLM_API_KEY}',
                'Content-Type': 'application/json'
            }
            
            # Get conversation history
            history = conversations.get(sender, [])
            
            payload = {
                'message': message,
                'mode': CONFIG['anythingllm']['mode'],
                'sessionId': f"signal-{sender}"
            }
            
            logger.info(f"Querying AnythingLLM: {message[:50]}...")
            
            response = requests.post(
                url,
                headers=headers,
                json=payload,
                timeout=CONFIG['bot']['timeout_seconds']
            )
            
            if response.status_code == 200:
                data = response.json()
                answer = data.get('textResponse', '')
                
                # Update conversation history
                history.append({'role': 'user', 'content': message})
                history.append({'role': 'assistant', 'content': answer})
                
                # Keep only last N messages
                limit = CONFIG['features']['history_limit']
                conversations[sender] = history[-limit:]
                
                logger.info(f"AnythingLLM response: {answer[:100]}...")
                return answer
            else:
                logger.error(f"AnythingLLM error: {response.status_code} - {response.text}")
                return None
                
        except Exception as e:
            logger.error(f"Error querying AnythingLLM: {e}", exc_info=True)
            return None
    
    def send_signal_message(self, recipient: str, message: str):
        """Send message via Signal REST API"""
        try:
            url = f"{SIGNAL_API_URL}/v2/send"
            
            # Truncate if too long
            max_length = CONFIG['bot']['max_message_length']
            if len(message) > max_length:
                message = message[:max_length-50] + "\n\n[Message truncated]"
            
            payload = {
                'message': message,
                'number': SIGNAL_PHONE,
                'recipients': [recipient]
            }
            
            logger.info(f"Sending Signal message to {recipient}: {message[:50]}...")
            
            response = requests.post(url, json=payload, timeout=30)
            
            if response.status_code == 201:
                logger.info(f"Message sent successfully to {recipient}")
            else:
                logger.error(f"Failed to send message: {response.status_code} - {response.text}")
                
        except Exception as e:
            logger.error(f"Error sending Signal message: {e}", exc_info=True)


def main():
    """Start webhook server"""
    logger.info(f"Starting {BOT_NAME} on port {PORT}")
    logger.info(f"Signal API: {SIGNAL_API_URL}")
    logger.info(f"AnythingLLM: {ANYTHINGLLM_URL}")
    logger.info(f"Workspace: {ANYTHINGLLM_WORKSPACE}")
    
    server = HTTPServer(('0.0.0.0', PORT), SignalWebhookHandler)
    
    try:
        logger.info(f"✅ {BOT_NAME} is ready to receive webhooks")
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Shutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()
