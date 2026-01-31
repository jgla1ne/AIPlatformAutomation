#!/bin/bash
set -euo pipefail

# ============================================
# AI Platform - Deploy ClawdBot v5.0
# Signal messaging bot with AI integration
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="/var/log/ai-platform-clawdbot.log"

sudo touch "$LOG_FILE" 2>/dev/null || LOG_FILE="$HOME/ai-platform-clawdbot.log"
sudo chown $USER:$USER "$LOG_FILE" 2>/dev/null || true
exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================
# Load Environment
# ============================================
load_environment() {
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        echo -e "${RED}❌ .env not found${NC}"
        exit 1
    fi

    source "$SCRIPT_DIR/.env"

    if [[ -f "$SCRIPT_DIR/.secrets" ]]; then
        source "$SCRIPT_DIR/.secrets"
    fi
}

# ============================================
# Verify Prerequisites
# ============================================
verify_prerequisites() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Deploy ClawdBot v5.0${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    echo -e "${BLUE}[1/8] Verifying prerequisites...${NC}"

    local all_ready=true

    # Check Signal number configured
    if [[ -z "${SIGNAL_NUMBER:-}" ]]; then
        echo -e "   ${RED}❌ SIGNAL_NUMBER not configured${NC}"
        echo "   Run: ./3-link-signal-device.sh"
        all_ready=false
    else
        echo -e "   ${GREEN}✅ Signal number: $SIGNAL_NUMBER${NC}"
    fi

    # Check Signal API
    if curl -sf http://localhost:8080/v1/health &> /dev/null; then
        echo -e "   ${GREEN}✅ Signal API responding${NC}"
    else
        echo -e "   ${RED}❌ Signal API not responding${NC}"
        all_ready=false
    fi

    # Check Signal account registered
    local accounts=$(curl -sf http://localhost:8080/v1/accounts || echo "[]")
    if echo "$accounts" | jq -e '.[] | select(.number != null)' &> /dev/null; then
        echo -e "   ${GREEN}✅ Signal device registered${NC}"
    else
        echo -e "   ${RED}❌ Signal device not registered${NC}"
        echo "   Run: ./3-link-signal-device.sh"
        all_ready=false
    fi

    # Check Ollama
    if curl -sf http://localhost:11434/api/tags &> /dev/null; then
        echo -e "   ${GREEN}✅ Ollama responding${NC}"
    else
        echo -e "   ${RED}❌ Ollama not responding${NC}"
        all_ready=false
    fi

    # Check AnythingLLM (optional)
    if curl -sf http://localhost:3001/ &> /dev/null; then
        echo -e "   ${GREEN}✅ AnythingLLM responding${NC}"
    else
        echo -e "   ${YELLOW}⚠️  AnythingLLM not responding (optional)${NC}"
    fi

    # Check LiteLLM (optional)
    if curl -sf http://localhost:4000/health &> /dev/null; then
        echo -e "   ${GREEN}✅ LiteLLM responding${NC}"
    else
        echo -e "   ${YELLOW}⚠️  LiteLLM not responding (optional)${NC}"
    fi

    # Check API keys
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        echo -e "   ${GREEN}✅ Claude API key configured${NC}"
    else
        echo -e "   ${YELLOW}⚠️  ANTHROPIC_API_KEY not set (will use Ollama)${NC}"
    fi

    if [[ "$all_ready" != "true" ]]; then
        echo ""
        echo -e "${RED}❌ Prerequisites not met${NC}"
        exit 1
    fi

    echo -e "   ${GREEN}✅ All prerequisites met${NC}"
}

# ============================================
# Create ClawdBot Application
# ============================================
create_clawdbot_app() {
    echo -e "\n${BLUE}[2/8] Creating ClawdBot application...${NC}"

    local app_dir="$CLAWDBOT_DATA"
    mkdir -p "$app_dir/config" "$app_dir/logs" "$app_dir/data"

    # Create main bot script
    cat > "$app_dir/clawdbot.py" <<'PYTHON_EOF'
#!/usr/bin/env python3
"""
ClawdBot - Signal AI Assistant
Connects Signal messages to AI providers (Claude, Ollama, LiteLLM, AnythingLLM)
"""

import os
import sys
import time
import json
import logging
import requests
import yaml
from datetime import datetime
from typing import Dict, List, Optional
import signal as signal_module

# Configuration
CONFIG_PATH = os.getenv('CONFIG_PATH', '/app/config/config.yaml')
SIGNAL_API_URL = os.getenv('SIGNAL_API_URL', 'http://signal-api:8080')
SIGNAL_NUMBER = os.getenv('SIGNAL_NUMBER')

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/app/logs/clawdbot.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('ClawdBot')

class ClawdBot:
    def __init__(self):
        self.config = self.load_config()
        self.running = True
        self.conversation_history = {}

        # AI Provider setup
        self.primary_provider = self.config['ai_providers']['primary']
        self.setup_ai_providers()

        logger.info(f"ClawdBot initialized for {SIGNAL_NUMBER}")
        logger.info(f"Primary AI provider: {self.primary_provider}")

    def load_config(self) -> Dict:
        """Load configuration from YAML"""
        try:
            with open(CONFIG_PATH, 'r') as f:
                return yaml.safe_load(f)
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
            sys.exit(1)

    def setup_ai_providers(self):
        """Setup AI provider connections"""
        providers = self.config['ai_providers']

        # Claude/Anthropic
        self.anthropic_key = os.getenv('ANTHROPIC_API_KEY')
        if self.anthropic_key:
            logger.info("✅ Claude API available")

        # Ollama
        self.ollama_url = os.getenv('OLLAMA_API_URL', 'http://ollama:11434')
        try:
            resp = requests.get(f"{self.ollama_url}/api/tags", timeout=2)
            if resp.status_code == 200:
                models = [m['name'] for m in resp.json().get('models', [])]
                logger.info(f"✅ Ollama available: {len(models)} models")
        except:
            logger.warning("⚠️  Ollama not available")

        # LiteLLM
        self.litellm_url = os.getenv('LITELLM_API_URL', 'http://litellm:4000')
        self.litellm_key = os.getenv('LITELLM_API_KEY')

        # AnythingLLM
        self.anythingllm_url = os.getenv('ANYTHINGLLM_API_URL', 'http://anythingllm:3001')
        self.anythingllm_key = os.getenv('ANYTHINGLLM_API_KEY')

    def get_ai_response(self, message: str, sender: str) -> str:
        """Get AI response using configured provider"""

        # Get conversation context
        context = self.conversation_history.get(sender, [])
        context.append({"role": "user", "content": message})

        # Try primary provider first
        if self.primary_provider == 'claude' and self.anthropic_key:
            response = self.query_claude(context)
        elif self.primary_provider == 'ollama':
            response = self.query_ollama(context)
        elif self.primary_provider == 'litellm':
            response = self.query_litellm(context)
        elif self.primary_provider == 'anythingllm':
            response = self.query_anythingllm(message, sender)
        else:
            # Fallback to Ollama
            response = self.query_ollama(context)

        # Update conversation history
        if response:
            context.append({"role": "assistant", "content": response})
            # Keep last N messages
            max_history = self.config['bot']['conversation_memory']
            self.conversation_history[sender] = context[-max_history:]

        return response or "Sorry, I couldn't process that request."

    def query_claude(self, context: List[Dict]) -> Optional[str]:
        """Query Claude API"""
        try:
            import anthropic

            client = anthropic.Anthropic(api_key=self.anthropic_key)

            response = client.messages.create(
                model="claude-3-5-sonnet-20241022",
                max_tokens=1024,
                messages=context
            )

            return response.content[0].text

        except Exception as e:
            logger.error(f"Claude API error: {e}")
            return None

    def query_ollama(self, context: List[Dict]) -> Optional[str]:
        """Query Ollama"""
        try:
            model = self.config['ai_providers']['ollama_model']

            response = requests.post(
                f"{self.ollama_url}/api/chat",
                json={
                    "model": model,
                    "messages": context,
                    "stream": False
                },
                timeout=30
            )

            if response.status_code == 200:
                return response.json()['message']['content']

        except Exception as e:
            logger.error(f"Ollama error: {e}")

        return None

    def query_litellm(self, context: List[Dict]) -> Optional[str]:
        """Query LiteLLM proxy"""
        try:
            response = requests.post(
                f"{self.litellm_url}/chat/completions",
                headers={"Authorization": f"Bearer {self.litellm_key}"},
                json={
                    "model": "ollama/llama3.2",
                    "messages": context
                },
                timeout=30
            )

            if response.status_code == 200:
                return response.json()['choices'][0]['message']['content']

        except Exception as e:
            logger.error(f"LiteLLM error: {e}")

        return None

    def query_anythingllm(self, message: str, sender: str) -> Optional[str]:
        """Query AnythingLLM workspace"""
        try:
            workspace_slug = self.config['ai_providers'].get('anythingllm_workspace', 'default')

            response = requests.post(
                f"{self.anythingllm_url}/api/v1/workspace/{workspace_slug}/chat",
                headers={
                    "Authorization": f"Bearer {self.anythingllm_key}",
                    "Content-Type": "application/json"
                },
                json={
                    "message": message,
                    "mode": "chat"
                },
                timeout=30
            )

            if response.status_code == 200:
                return response.json().get('textResponse', '')

        except Exception as e:
            logger.error(f"AnythingLLM error: {e}")

        return None

    def send_message(self, recipient: str, message: str) -> bool:
        """Send Signal message"""
        try:
            response = requests.post(
                f"{SIGNAL_API_URL}/v2/send",
                json={
                    "message": message,
                    "number": SIGNAL_NUMBER,
                    "recipients": [recipient]
                },
                timeout=10
            )

            return response.status_code == 201

        except Exception as e:
            logger.error(f"Failed to send message: {e}")
            return False

    def receive_messages(self) -> List[Dict]:
        """Poll for new messages"""
        try:
            response = requests.get(
                f"{SIGNAL_API_URL}/v1/receive/{SIGNAL_NUMBER}",
                timeout=10
            )

            if response.status_code == 200:
                return response.json()

        except Exception as e:
            logger.error(f"Failed to receive messages: {e}")

        return []

    def process_message(self, msg: Dict):
        """Process incoming message"""
        try:
            envelope = msg.get('envelope', {})
            sender = envelope.get('source') or envelope.get('sourceNumber')

            if not sender:
                return

            # Get message text
            message_text = None
            if 'dataMessage' in envelope:
                message_text = envelope['dataMessage'].get('message')
            elif 'syncMessage' in envelope:
                sent = envelope['syncMessage'].get('sentMessage', {})
                message_text = sent.get('message')

            if not message_text:
                return

            logger.info(f"📨 Message from {sender}: {message_text[:50]}...")

            # Check if from admin
            admin_numbers = self.config['security']['admin_numbers']
            is_admin = sender in admin_numbers

            # Check allowed numbers
            allowed = self.config['security']['allowed_numbers']
            if allowed and sender not in allowed and not is_admin:
                logger.warning(f"⛔ Blocked message from {sender}")
                return

            # Handle commands
            if message_text.startswith('/'):
                self.handle_command(sender, message_text)
                return

            # Get AI response
            response = self.get_ai_response(message_text, sender)

            # Send response
            if self.send_message(sender, response):
                logger.info(f"✅ Response sent to {sender}")
            else:
                logger.error(f"❌ Failed to send response to {sender}")

        except Exception as e:
            logger.error(f"Error processing message: {e}")

    def handle_command(self, sender: str, command: str):
        """Handle bot commands"""
        cmd = command.lower().strip()

        if cmd == '/help':
            help_text = (
                f"🤖 {self.config['bot']['name']} Commands:\n\n"
                "/help - Show this message\n"
                "/status - Bot status\n"
                "/clear - Clear conversation history\n"
                "/provider - Show AI provider"
            )
            self.send_message(sender, help_text)

        elif cmd == '/status':
            status = f"✅ Online\nProvider: {self.primary_provider}\nTime: {datetime.now()}"
            self.send_message(sender, status)

        elif cmd == '/clear':
            if sender in self.conversation_history:
                del self.conversation_history[sender]
            self.send_message(sender, "🗑️ Conversation history cleared")

        elif cmd == '/provider':
            self.send_message(sender, f"AI Provider: {self.primary_provider}")

    def run(self):
        """Main bot loop"""
        logger.info("🚀 ClawdBot starting...")

        # Send startup message to admin
        admin_numbers = self.config['security']['admin_numbers']
        for admin in admin_numbers:
            self.send_message(admin, f"✅ {self.config['bot']['name']} started at {datetime.now()}")

        poll_interval = 2  # seconds

        while self.running:
            try:
                messages = self.receive_messages()

                for msg in messages:
                    self.process_message(msg)

                time.sleep(poll_interval)

            except KeyboardInterrupt:
                logger.info("Shutting down...")
                self.running = False
            except Exception as e:
                logger.error(f"Error in main loop: {e}")
                time.sleep(5)

if __name__ == '__main__':
    if not SIGNAL_NUMBER:
        logger.error("SIGNAL_NUMBER not set")
        sys.exit(1)

    bot = ClawdBot()
    bot.run()
PYTHON_EOF

    chmod +x "$app_dir/clawdbot.py"
    echo -e "   ${GREEN}✅ ClawdBot application created${NC}"
}

# ============================================
# Create Configuration
# ============================================
create_config() {
    echo -e "\n${BLUE}[3/8] Creating configuration...${NC}"

    local config_dir="$CLAWDBOT_DATA/config"

    # Determine primary provider
    local primary_provider="ollama"
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        primary_provider="claude"
    fi

    cat > "$config_dir/config.yaml" <<CONFIG_EOF
# ClawdBot Configuration

ai_providers:
  primary: "$primary_provider"

  # Ollama (local)
  ollama_model: "llama3.2:latest"

  # Claude (Anthropic)
  claude_model: "claude-3-5-sonnet-20241022"

  # LiteLLM (proxy)
  litellm_model: "ollama/llama3.2"

  # AnythingLLM (RAG)
  anythingllm_workspace: "default"

bot:
  name: "ClawdBot"
  response_timeout: 30
  max_message_length: 4000
  conversation_memory: 10

logging:
  level: "INFO"
  file: "/app/logs/clawdbot.log"

security:
  allowed_numbers: []  # Empty = allow all
  admin_numbers: ["$SIGNAL_NUMBER"]
CONFIG_EOF

    echo -e "   ${GREEN}✅ Configuration created (primary: $primary_provider)${NC}"
}

# ============================================
# Create Dockerfile
# ============================================
create_dockerfile() {
    echo -e "\n${BLUE}[4/8] Creating Dockerfile...${NC}"

    cat > "$CLAWDBOT_DATA/Dockerfile" <<'DOCKERFILE_EOF'
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir \
    requests==2.31.0 \
    pyyaml==6.0.1 \
    anthropic==0.39.0

# Copy application
COPY clawdbot.py /app/
RUN chmod +x /app/clawdbot.py

# Create directories
RUN mkdir -p /app/logs /app/data /app/config

CMD ["python", "/app/clawdbot.py"]
DOCKERFILE_EOF

    echo -e "   ${GREEN}✅ Dockerfile created${NC}"
}

# ============================================
# Create Docker Compose
# ============================================
create_docker_compose() {
    echo -e "\n${BLUE}[5/8] Creating docker-compose.yml...${NC}"

    mkdir -p "$SCRIPT_DIR/stacks/clawdbot"

    cat > "$SCRIPT_DIR/stacks/clawdbot/docker-compose.yml" <<COMPOSE_EOF
services:
  clawdbot:
    build:
      context: $CLAWDBOT_DATA
      dockerfile: Dockerfile
    container_name: clawdbot
    restart: unless-stopped
    environment:
      - SIGNAL_API_URL=http://signal-api:8080
      - SIGNAL_NUMBER=$SIGNAL_NUMBER
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
      - OLLAMA_API_URL=http://ollama:11434
      - LITELLM_API_URL=http://litellm:4000
      - LITELLM_API_KEY=${LITELLM_MASTER_KEY:-}
      - ANYTHINGLLM_API_URL=http://anythingllm:3001
      - ANYTHINGLLM_API_KEY=${ANYTHINGLLM_API_KEY:-}
      - CONFIG_PATH=/app/config/config.yaml
    volumes:
      - $CLAWDBOT_DATA/config:/app/config:ro
      - $CLAWDBOT_DATA/logs:/app/logs
      - $CLAWDBOT_DATA/data:/app/data
    networks:
      - ai-platform-network
    depends_on:
      - signal-api

networks:
  ai-platform-network:
    external: true
    name: ai-platform-network
COMPOSE_EOF

    echo -e "   ${GREEN}✅ docker-compose.yml created${NC}"
}

# ============================================
# Build and Deploy
# ============================================
build_and_deploy() {
    echo -e "\n${BLUE}[6/8] Building ClawdBot image...${NC}"

    cd "$SCRIPT_DIR/stacks/clawdbot"

    if docker compose build; then
        echo -e "   ${GREEN}✅ Image built successfully${NC}"
    else
        echo -e "   ${RED}❌ Build failed${NC}"
        exit 1
    fi

    echo -e "\n${BLUE}[7/8] Starting ClawdBot...${NC}"

    docker compose up -d

    echo -e "   ${GREEN}✅ ClawdBot started${NC}"
}

# ============================================
# Verify Deployment
# ============================================
verify_deployment() {
    echo -e "\n${BLUE}[8/8] Verifying deployment...${NC}"

    sleep 5

    if docker ps | grep -q "clawdbot"; then
        echo -e "   ${GREEN}✅ ClawdBot container running${NC}"

        # Check logs
        echo ""
        echo "Recent logs:"
        docker logs --tail 20 clawdbot 2>&1 | sed 's/^/   /'
    else
        echo -e "   ${RED}❌ ClawdBot container not running${NC}"
        echo ""
        echo "Checking logs:"
        docker logs clawdbot 2>&1 | tail -20 | sed 's/^/   /'
        exit 1
    fi
}

# ============================================
# Print Summary
# ============================================
print_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}ClawdBot Deployed!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}Configuration:${NC}"
    echo "  • Signal Number: $SIGNAL_NUMBER"
    echo "  • Container:     clawdbot"
    echo "  • Config:        $CLAWDBOT_DATA/config/config.yaml"
    echo "  • Logs:          $CLAWDBOT_DATA/logs/"
    echo ""
    echo -e "${BLUE}Test ClawdBot:${NC}"
    echo "  1. Send a Signal message to $SIGNAL_NUMBER"
    echo "  2. ClawdBot will respond via AI"
    echo ""
    echo -e "${BLUE}Bot Commands:${NC}"
    echo "  /help      - Show help message"
    echo "  /status    - Bot status"
    echo "  /clear     - Clear conversation history"
    echo "  /provider  - Show AI provider"
    echo ""
    echo -e "${BLUE}Management:${NC}"
    echo "  • View logs:      docker logs -f clawdbot"
    echo "  • Restart:        docker restart clawdbot"
    echo "  • Stop:           docker stop clawdbot"
    echo "  • Edit config:    vim $CLAWDBOT_DATA/config/config.yaml"
    echo "  • Rebuild:        cd stacks/clawdbot && docker compose up -d --build"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Test by sending a message to $SIGNAL_NUMBER"
    echo "  2. Configure all services:"
    echo "     ./5-configure-services.sh"
    echo ""
}

# ============================================
# Main Execution
# ============================================
main() {
    load_environment
    verify_prerequisites
    create_clawdbot_app
    create_config
    create_dockerfile
    create_docker_compose
    build_and_deploy
    verify_deployment
    print_summary
}

main "$@"

chmod +x ~/ai-platform-installer/scripts/4-deploy-clawdbot.sh
