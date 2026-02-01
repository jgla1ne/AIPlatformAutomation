FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir \
    fastapi==0.104.1 \
    uvicorn==0.24.0 \
    httpx==0.25.1 \
    python-dotenv==1.0.0 \
    pydantic==2.5.0 \
    aiofiles==23.2.1

COPY config/clawdbot/app.py /app/app.py
COPY config/clawdbot/config.json /app/config/config.json

EXPOSE 8000

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
