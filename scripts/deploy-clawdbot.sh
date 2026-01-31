#!/bin/bash
set -eo pipefail

# ============================================
# ClawdBot Deployment Script v1.1
# Handles pre-linked Signal devices
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/ai-platform-clawdbot.log"

sudo touch "$LOG_FILE"
sudo chown $USER:$USER "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ClawdBot Deployment v1.1${NC}"
echo -e "${BLUE}Started: $(date)${NC}"
echo -e "${BLUE}========================================${NC}"

# ============================================
# Load Environment
# ============================================
load_environment() {
    echo -e "\n${BLUE}[1/8] Loading environment...${NC}"
    
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        echo -e "   ${RED}❌ .env file not found${NC}"
        exit 1
    fi
    
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
    
    echo -e "   ${GREEN}✅ Environment loaded${NC}"
}

# ============================================
# Detect and Configure Signal Number
# ============================================
detect_signal_number() {
    echo -e "\n${BLUE}[2/8] Detecting Signal configuration...${NC}"
    
    # Try to get linked accounts from Signal CLI
    local accounts=$(docker exec signal-cli signal-cli listAccounts 2>/dev/null || echo "")
    
    if [[ -n "$accounts" ]]; then
        # Extract first phone number
        local detected_number=$(echo "$accounts" | grep -oE '\+[0-9]+' | head -1)
        
        if [[ -n "$detected_number" ]]; then
            echo -e "   ${GREEN}✅ Detected linked Signal number: $detected_number${NC}"
            
            # Check if SIGNAL_NUMBER is already set in .env
            if [[ -z "$SIGNAL_NUMBER" ]] || [[ "$SIGNAL_NUMBER" != "$detected_number" ]]; then
                echo -e "   ${YELLOW}Updating .env with detected number${NC}"
                
                # Update or add SIGNAL_NUMBER in .env
                if grep -q "^SIGNAL_NUMBER=" "$SCRIPT_DIR/.env"; then
                    sed -i "s|^SIGNAL_NUMBER=.*|SIGNAL_NUMBER=$detected_number|" "$SCRIPT_DIR/.env"
                else
                    echo "SIGNAL_NUMBER=$detected_number" >> "$SCRIPT_DIR/.env"
                fi
                
                # Reload environment
                source "$SCRIPT_DIR/.env"
            fi
        else
            echo -e "   ${RED}❌ No Signal number detected${NC}"
            prompt_signal_setup
        fi
    else
        echo -e "   ${YELLOW}⚠️  Unable to query Signal CLI${NC}"
        prompt_signal_setup
    fi
}

prompt_signal_setup() {
    echo ""
    echo -e "${YELLOW}Signal doesn't appear to be linked yet.${NC}"
    echo ""
    echo "You have two options:"
    echo ""
    echo "  1. Web UI (Recommended - what you already did):"
    echo "     http://ai.datasquiz.net:8080/v1/qrcodelink?device_name=signal-api"
    echo ""
    echo "  2. Command line:"
    echo "     docker exec -it signal-cli signal-cli link -n ai-platform"
    echo ""
    read -p "Have you already linked Signal? (y/n): " linked
    
    if [[ "$linked" != "y" ]]; then
        echo ""
        echo "Please link Signal first, then run this script again."
        exit 1
    fi
    
    # Manual entry
    echo ""
    read -p "Enter your Signal phone number (e.g., +1234567890): " manual_number
    
    if [[ -z "$manual_number" ]]; then
        echo -e "${RED}No number provided. Exiting.${NC}"
        exit 1
    fi
    
    # Add to .env
    if grep -q "^SIGNAL_NUMBER=" "$SCRIPT_DIR/.env"; then
        sed -i "s|^SIGNAL_NUMBER=.*|SIGNAL_NUMBER=$manual_number|" "$SCRIPT_DIR/.env"
    else
        echo "SIGNAL_NUMBER=$manual_number" >> "$SCRIPT_DIR/.env"
    fi
    
    source "$SCRIPT_DIR/.env"
    echo -e "   ${GREEN}✅ Signal number set to: $SIGNAL_NUMBER${NC}"
}

# ============================================
# Verify Prerequisites
# ============================================
verify_prerequisites() {
    echo -e "\n${BLUE}[3/8] Verifying prerequisites...${NC}"
    
    local all_ready=true
    
    # Verify Signal number is set
    if [[ -z "$SIGNAL_NUMBER" ]]; then
        echo -e "   ${RED}❌ SIGNAL_NUMBER not configured${NC}"
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
    
    # Check Ollama
    if curl -sf http://localhost:11434/api/tags &> /dev/null; then
        echo -e "   ${GREEN}✅ Ollama responding${NC}"
    else
        echo -e "   ${RED}❌ Ollama not responding${NC}"
        all_ready=false
    fi
    
    # Check LiteLLM
    if curl -sf http://localhost:4000/health &> /dev/null; then
        echo -e "   ${GREEN}✅ LiteLLM responding${NC}"
    else
        echo -e "   ${YELLOW}⚠️  LiteLLM not responding (optional)${NC}"
    fi
    
    # Check Claude API key
    if [[ -z "$ANTHROPIC_API_KEY" ]]; then
        echo -e "   ${YELLOW}⚠️  ANTHROPIC_API_KEY not set${NC}"
        echo -e "   ${BLUE}   Bot will use Ollama instead${NC}"
    else
        echo -e "   ${GREEN}✅ Claude API key configured${NC}"
    fi
    
    if [[ "$all_ready" != "true" ]]; then
        echo -e "\n${RED}Prerequisites not met. Please fix the issues above.${NC}"
        exit 1
    fi
    
    echo -e "   ${GREEN}✅ All prerequisites met${NC}"
}

# ============================================
# Create ClawdBot Application
# (Keep all the previous create_clawdbot_* functions here)
# ============================================

create_clawdbot_config() {
    echo -e "\n${BLUE}[4/8] Creating ClawdBot configuration...${NC}"
    
    mkdir -p "$DATA_PATH/clawdbot/config"
    
    # Determine default AI provider
    local default_provider="ollama"
    if [[ -n "$ANTHROPIC_API_KEY" ]]; then
        default_provider="claude"
    fi
    
    cat > "$DATA_PATH/clawdbot/config/config.yaml" <<CONFIG_EOF
# ClawdBot Configuration
signal:
  api_url: http://signal-cli:8080
  number: "${SIGNAL_NUMBER}"
  
ai:
  # Primary AI provider
  provider: "${default_provider}"  # Options: claude, ollama, litellm
  
  # Claude configuration (if provider=claude)
  claude:
    api_key: "${ANTHROPIC_API_KEY:-}"
    model: "claude-3-5-sonnet-20241022"
    max_tokens: 4096
    
  # Ollama configuration (if provider=ollama)
  ollama:
    api_url: http://ollama:11434
    model: "llama3.2"
    
  # LiteLLM configuration (if provider=litellm)
  litellm:
    api_url: http://litellm:4000
    api_key: "${LITELLM_API_KEY:-}"
    model: "llama3.2"

# Bot behavior
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
  admin_numbers: ["${SIGNAL_NUMBER}"]
CONFIG_EOF
    
    echo -e "   ${GREEN}✅ Configuration created (using $default_provider)${NC}"
}

# [Keep all other create_clawdbot_* functions from previous version]

create_clawdbot_compose() {
    echo -e "\n${BLUE}[5/8] Creating ClawdBot Docker Compose...${NC}"
    
    mkdir -p "$SCRIPT_DIR/stacks/clawdbot"
    
    cat > "$SCRIPT_DIR/stacks/clawdbot/docker-compose.yml" <<'COMPOSE_EOF'
services:
  clawdbot:
    build:
      context: ${DATA_PATH}/clawdbot
      dockerfile: Dockerfile
    container_name: clawdbot
    restart: unless-stopped
    environment:
      - SIGNAL_API_URL=http://signal-cli:8080
      - SIGNAL_NUMBER=${SIGNAL_NUMBER}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - OLLAMA_API_URL=http://ollama:11434
      - LITELLM_API_URL=http://litellm:4000
      - LITELLM_API_KEY=${LITELLM_API_KEY}
      - CONFIG_PATH=/app/config/config.yaml
    volumes:
      - ${DATA_PATH}/clawdbot/config:/app/config:ro
      - ${DATA_PATH}/clawdbot/logs:/app/logs
      - ${DATA_PATH}/clawdbot/data:/app/data
    networks:
      - ai-platform-network
    depends_on:
      - signal-cli
      - ollama

networks:
  ai-platform-network:
    external: true
    name: ${NETWORK_NAME}
COMPOSE_EOF
    
    cp "$SCRIPT_DIR/.env" "$SCRIPT_DIR/stacks/clawdbot/.env"
    
    echo -e "   ${GREEN}✅ Docker Compose created${NC}"
}

create_clawdbot_dockerfile() {
    echo -e "\n${BLUE}[6/8] Creating ClawdBot Dockerfile...${NC}"
    
    cat > "$DATA_PATH/clawdbot/Dockerfile" <<'DOCKERFILE_EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    gcc \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
COPY config/ ./config/

RUN mkdir -p /app/logs /app/data

ENV PYTHONPATH=/app

CMD ["python", "src/main.py"]
DOCKERFILE_EOF
    
    echo -e "   ${GREEN}✅ Dockerfile created${NC}"
}

create_clawdbot_app() {
    echo -e "\n${BLUE}[7/8] Creating ClawdBot application...${NC}"
    
    mkdir -p "$DATA_PATH/clawdbot/src"
    
    # [Keep all the Python files from previous version - main.py, config.py, bot.py]
    
    cat > "$DATA_PATH/clawdbot/src/main.py" <<'MAIN_EOF'
import asyncio
import logging
import signal
import sys
from pathlib import Path

from bot import ClawdBot
from config import load_config

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/app/logs/clawdbot.log')
    ]
)

logger = logging.getLogger(__name__)

async def main():
    try:
        config = load_config('/app/config/config.yaml')
        bot = ClawdBot(config)
        
        def signal_handler(sig, frame):
            logger.info("Received shutdown signal")
            asyncio.create_task(bot.stop())
        
        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)
        
        logger.info("Starting ClawdBot...")
        await bot.start()
        
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())
MAIN_EOF

    cat > "$DATA_PATH/clawdbot/src/config.py" <<'CONFIG_EOF'
import yaml
from pathlib import Path
from typing import Dict, Any

def load_config(config_path: str) -> Dict[str, Any]:
    config_file = Path(config_path)
    
    if not config_file.exists():
        raise FileNotFoundError(f"Config file not found: {config_path}")
    
    with open(config_file, 'r') as f:
        config = yaml.safe_load(f)
    
    return config
CONFIG_EOF

    cat > "$DATA_PATH/clawdbot/src/bot.py" <<'BOT_EOF'
import asyncio
import logging
from typing import Dict, List, Optional
import aiohttp
from datetime import datetime

logger = logging.getLogger(__name__)

class ClawdBot:
    def __init__(self, config: Dict):
        self.config = config
        self.signal_api = config['signal']['api_url']
        self.signal_number = config['signal']['number']
        self.running = False
        self.session: Optional[aiohttp.ClientSession] = None
        
        self.ai_provider = config['ai']['provider']
        self._init_ai_client()
        
        self.conversations: Dict[str, List[Dict]] = {}
        self.max_memory = config['bot'].get('conversation_memory', 10)
    
    def _init_ai_client(self):
        if self.ai_provider == "claude":
            from anthropic import AsyncAnthropic
            self.ai_client = AsyncAnthropic(
                api_key=self.config['ai']['claude']['api_key']
            )
            self.ai_model = self.config['ai']['claude']['model']
        elif self.ai_provider == "ollama":
            self.ai_url = self.config['ai']['ollama']['api_url']
            self.ai_model = self.config['ai']['ollama']['model']
        elif self.ai_provider == "litellm":
            self.ai_url = self.config['ai']['litellm']['api_url']
            self.ai_model = self.config['ai']['litellm']['model']
            self.ai_key = self.config['ai']['litellm']['api_key']
    
    async def start(self):
        self.running = True
        self.session = aiohttp.ClientSession()
        
        logger.info(f"ClawdBot started with {self.ai_provider} provider")
        logger.info(f"Listening on Signal number: {self.signal_number}")
        
        await self._poll_messages()
    
    async def stop(self):
        self.running = False
        if self.session:
            await self.session.close()
        logger.info("ClawdBot stopped")
    
    async def _poll_messages(self):
        while self.running:
            try:
                async with self.session.get(
                    f"{self.signal_api}/v1/receive/{self.signal_number}"
                ) as response:
                    if response.status == 200:
                        messages = await response.json()
                        for msg in messages:
                            await self._handle_message(msg)
                    
                await asyncio.sleep(1)
                
            except Exception as e:
                logger.error(f"Error polling messages: {e}")
                await asyncio.sleep(5)
    
    async def _handle_message(self, message: Dict):
        try:
            envelope = message.get('envelope', {})
            source = envelope.get('source') or envelope.get('sourceNumber')
            data_message = envelope.get('dataMessage', {})
            text = data_message.get('message', '').strip()
            
            if not text or not source:
                return
            
            logger.info(f"Received from {source}: {text}")
            
            if not self._is_allowed(source):
                logger.warning(f"Blocked message from unauthorized number: {source}")
                return
            
            response = await self._generate_response(source, text)
            await self._send_message(source, response)
            
        except Exception as e:
            logger.error(f"Error handling message: {e}", exc_info=True)
    
    def _is_allowed(self, number: str) -> bool:
        allowed = self.config['security'].get('allowed_numbers', [])
        if not allowed:
            return True
        return number in allowed
    
    async def _generate_response(self, sender: str, message: str) -> str:
        try:
            if sender not in self.conversations:
                self.conversations[sender] = []
            
            self.conversations[sender].append({
                'role': 'user',
                'content': message,
                'timestamp': datetime.now().isoformat()
            })
            
            if len(self.conversations[sender]) > self.max_memory * 2:
                self.conversations[sender] = self.conversations[sender][-self.max_memory * 2:]
            
            if self.ai_provider == "claude":
                response = await self._claude_response(sender, message)
            elif self.ai_provider in ["ollama", "litellm"]:
                response = await self._ollama_response(sender, message)
            else:
                response = "Error: Unknown AI provider"
            
            self.conversations[sender].append({
                'role': 'assistant',
                'content': response,
                'timestamp': datetime.now().isoformat()
            })
            
            return response
            
        except Exception as e:
            logger.error(f"Error generating response: {e}", exc_info=True)
            return "Sorry, I encountered an error processing your message."
    
    async def _claude_response(self, sender: str, message: str) -> str:
        messages = [
            {'role': msg['role'], 'content': msg['content']}
            for msg in self.conversations[sender]
            if msg['role'] in ['user', 'assistant']
        ]
        
        response = await self.ai_client.messages.create(
            model=self.ai_model,
            max_tokens=self.config['ai']['claude']['max_tokens'],
            messages=messages
        )
        
        return response.content[0].text
    
    async def _ollama_response(self, sender: str, message: str) -> str:
        messages = [
            {'role': msg['role'], 'content': msg['content']}
            for msg in self.conversations[sender]
            if msg['role'] in ['user', 'assistant']
        ]
        
        headers = {}
        if self.ai_provider == "litellm":
            headers['Authorization'] = f'Bearer {self.ai_key}'
        
        async with self.session.post(
            f"{self.ai_url}/v1/chat/completions",
            json={
                'model': self.ai_model,
                'messages': messages,
                'stream': False
            },
            headers=headers
        ) as response:
            if response.status == 200:
                data = await response.json()
                return data['choices'][0]['message']['content']
            else:
                logger.error(f"AI API error: {response.status}")
                return "Sorry, the AI service is temporarily unavailable."
    
    async def _send_message(self, recipient: str, message: str):
        try:
            async with self.session.post(
                f"{self.signal_api}/v2/send",
                json={
                    'number': self.signal_number,
                    'recipients': [recipient],
                    'message': message
                }
            ) as response:
                if response.status == 201:
                    logger.info(f"Sent to {recipient}: {message[:50]}...")
                else:
                    logger.error(f"Failed to send message: {response.status}")
                    
        except Exception as e:
            logger.error(f"Error sending message: {e}")
BOT_EOF

    cat > "$DATA_PATH/clawdbot/requirements.txt" <<'REQUIREMENTS_EOF'
aiohttp==3.9.1
anthropic==0.18.1
pyyaml==6.0.1
python-dotenv==1.0.0
REQUIREMENTS_EOF
    
    echo -e "   ${GREEN}✅ ClawdBot application created${NC}"
}

deploy_clawdbot() {
    echo -e "\n${BLUE}[8/8] Deploying ClawdBot...${NC}"
    
    cd "$SCRIPT_DIR/stacks/clawdbot"
    
    if docker compose up -d --build; then
        echo -e "   ${GREEN}✅ ClawdBot deployed successfully${NC}"
        sleep 5
        
        echo -e "\n${BLUE}ClawdBot logs (last 20 lines):${NC}"
        docker logs clawdbot --tail 20
        
        return 0
    else
        echo -e "   ${RED}❌ ClawdBot deployment failed${NC}"
        return 1
    fi
}

show_summary() {
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}ClawdBot Deployment Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Configuration:"
    echo "  Signal number: $SIGNAL_NUMBER"
    echo "  AI provider:   $(grep 'provider:' $DATA_PATH/clawdbot/config/config.yaml | awk '{print $2}' | tr -d '"')"
    echo "  Data path:     $DATA_PATH/clawdbot"
    echo ""
    echo "Testing:"
    echo "  Send a message to $SIGNAL_NUMBER from another device"
    echo ""
    echo "Management:"
    echo "  View logs:   docker logs -f clawdbot"
    echo "  Restart:     docker restart clawdbot"
    echo "  Edit config: nano $DATA_PATH/clawdbot/config/config.yaml"
    echo ""
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAME|clawdbot|signal"
    echo ""
}

main() {
    load_environment
    detect_signal_number
    verify_prerequisites
    create_clawdbot_config
    create_clawdbot_compose
    create_clawdbot_dockerfile
    create_clawdbot_app
    deploy_clawdbot
    show_summary
}

main "$@"

chmod +x ~/ai-platform-installer/deploy-clawdbot.sh
