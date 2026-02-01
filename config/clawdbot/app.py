from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
import httpx
import os
import json
from typing import Optional

app = FastAPI(title="ClawdBot", version="1.0.0")

SIGNAL_API_URL = os.getenv("SIGNAL_API_URL", "http://signal-api:8080")
LITELLM_URL = os.getenv("LITELLM_URL", "http://litellm:4000")
LITELLM_API_KEY = os.getenv("LITELLM_API_KEY")
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD")

class Message(BaseModel):
    phone: str
    message: str

class SignalWebhook(BaseModel):
    envelope: dict

@app.get("/")
async def root():
    return {"status": "ClawdBot is running", "version": "1.0.0"}

@app.get("/health")
async def health():
    return {"status": "healthy"}

@app.post("/webhook/signal")
async def signal_webhook(data: SignalWebhook):
    """Receive messages from Signal and respond with AI"""
    try:
        envelope = data.envelope
        source = envelope.get("sourceNumber")
        message = envelope.get("dataMessage", {}).get("message", "")
        
        if not message:
            return {"status": "ignored"}
        
        # Get AI response
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{LITELLM_URL}/v1/chat/completions",
                headers={"Authorization": f"Bearer {LITELLM_API_KEY}"},
                json={
                    "model": "llama3.2",
                    "messages": [{"role": "user", "content": message}],
                    "max_tokens": 500
                },
                timeout=30.0
            )
            
            if response.status_code == 200:
                ai_response = response.json()["choices"][0]["message"]["content"]
                
                # Send response back via Signal
                await client.post(
                    f"{SIGNAL_API_URL}/v2/send",
                    json={
                        "number": source,
                        "recipients": [source],
                        "message": ai_response
                    },
                    timeout=10.0
                )
                
                return {"status": "responded"}
            else:
                return {"status": "error", "message": "AI request failed"}
    
    except Exception as e:
        print(f"Error: {e}")
        return {"status": "error", "message": str(e)}

@app.post("/send")
async def send_message(msg: Message, authorization: Optional[str] = Header(None)):
    """Send message via Signal (admin only)"""
    if authorization != f"Bearer {ADMIN_PASSWORD}":
        raise HTTPException(status_code=401, detail="Unauthorized")
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{SIGNAL_API_URL}/v2/send",
                json={
                    "number": msg.phone,
                    "recipients": [msg.phone],
                    "message": msg.message
                },
                timeout=10.0
            )
            
            if response.status_code == 201:
                return {"status": "sent"}
            else:
                raise HTTPException(status_code=500, detail="Failed to send message")
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
