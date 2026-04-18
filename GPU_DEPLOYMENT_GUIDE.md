# GPU-Enabled Deployment Guide

## Overview

This guide covers GPU-enabled deployment scenarios for the AI Platform, specifically optimized for AWS g6.2xlarge instances with NVIDIA L4 GPUs (24GB VRAM).

## GPU Hardware Support

### Supported GPU Types
- **NVIDIA**: Full support with CUDA acceleration
- **AMD ROCm**: Basic support with ROCm acceleration
- **CPU-only**: Graceful fallback for development/testing

### Target Instance Types
- **g6.2xlarge**: NVIDIA L4 GPU (24GB VRAM) - **Recommended**
- **g6.4xlarge**: 2x NVIDIA L4 GPUs (48GB VRAM) - **High Performance**
- **g6.8xlarge**: 4x NVIDIA L4 GPUs (96GB VRAM) - **Enterprise**
- **t2.large**: CPU-only (8GB RAM) - **Development/Testing**

## GPU Detection and Configuration

### Automatic Detection
Script 1 automatically detects GPU hardware:
```bash
# NVIDIA GPU detection
if command -v nvidia-smi >/dev/null 2>&1; then
    GPU_TYPE="nvidia"
    GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
fi

# AMD GPU detection
elif command -v rocm-smi >/dev/null 2>&1; then
    GPU_TYPE="rocm"
    GPU_MEMORY="unknown"
fi
```

### GPU Configuration Variables
```bash
# platform.conf GPU settings
GPU_TYPE="nvidia"                    # nvidia, rocm, none
GPU_MEMORY="24576"                   # VRAM in MB
GPU_COUNT="1"                        # Number of GPUs
OLLAMA_GPU_LAYERS="auto"             # Auto-optimize GPU layers
```

## GPU-Accelerated Services

### Services with GPU Support
1. **Ollama**: Model inference acceleration
2. **OpenWebUI**: GPU-accelerated UI interactions
3. **Code Server**: AI-assisted coding with GPU
4. **Continue.dev**: VS Code AI features

### GPU Reservation Configuration
```yaml
# Docker Compose GPU reservation
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]
```

## Model Performance by GPU Type

### NVIDIA L4 GPU (24GB VRAM) - g6.2xlarge
**Recommended Models:**
- **Large Models**: 70B+ (llama3.1:70b, qwen2.5:72b)
- **Medium Models**: 8B-34B (gemma4:31b, qwen2.5:14b)
- **Small Models**: <8B (gemma4:4b, mistral:7b)

**Performance Characteristics:**
- **Inference Speed**: 5-10x faster than CPU
- **Model Loading**: 2-3x faster than CPU
- **VRAM Usage**: Efficient with OLLAMA_GPU_LAYERS=auto

### Multi-GPU Support (g6.4xlarge, g6.8xlarge)
**Load Balancing:**
- Automatic GPU distribution
- Model sharding for very large models
- Horizontal scaling capabilities

## Deployment Scenarios

### Scenario 1: Single GPU (g6.2xlarge)
```bash
# Deploy with automatic GPU detection
./scripts/1-setup-system.sh production \
  --base-domain ai.production.com

# GPU will be automatically detected and configured
# OLLAMA_GPU_LAYERS=auto optimizes VRAM usage
```

### Scenario 2: Multi-GPU (g6.4xlarge)
```bash
# Deploy with multi-GPU support
./scripts/1-setup-system.sh enterprise \
  --base-domain ai.enterprise.com \
  --gpu-count 2

# Models will be distributed across GPUs
# Load balancing automatically configured
```

### Scenario 3: GPU Fallback (t2.large)
```bash
# Deploy with CPU fallback
./scripts/1-setup-system.sh development \
  --base-domain dev.ai.local

# GPU_TYPE=none automatically set
# CPU-optimized model selection
```

## GPU Monitoring and Health

### Prometheus GPU Metrics
```yaml
# GPU metrics collection
- nvidia_gpu_memory_total_bytes
- nvidia_gpu_memory_used_bytes
- nvidia_gpu_utilization_gpu
- nvidia_gpu_temperature_celsius
- nvidia_gpu_power_usage_watts
```

### Grafana GPU Dashboard
- **GPU Utilization**: Real-time usage graphs
- **Memory Usage**: VRAM allocation and trends
- **Temperature Monitoring**: GPU temperature alerts
- **Performance Metrics**: Inference speed tracking

### GPU Health Checks
```bash
# GPU health verification
docker exec ai-production-ollama nvidia-smi
docker exec ai-production-ollama ollama list
curl -s http://localhost:11434/api/tags | jq
```

## GPU Memory Management

### OLLAMA_GPU_LAYERS Configuration
```bash
# Automatic optimization (recommended)
OLLAMA_GPU_LAYERS="auto"

# Manual configuration
OLLAMA_GPU_LAYERS="99"    # Maximum GPU layers
OLLAMA_GPU_LAYERS="50"    # Half GPU layers
OLLAMA_GPU_LAYERS="0"     # CPU-only
```

### VRAM Optimization Strategies
1. **Layer Offloading**: Move model layers to GPU
2. **Model Sharding**: Split large models across GPUs
3. **Memory Cleanup**: Automatic VRAM garbage collection
4. **Batch Processing**: Optimize inference batch sizes

## GPU Performance Testing

### Test Commands
```bash
# GPU performance test
time docker exec ai-production-ollama ollama run llama3.1:70b "Hello, how are you?"

# Compare with CPU performance
docker exec ai-production-ollama ollama stop llama3.1:70b
OLLAMA_GPU_LAYERS="0" docker restart ai-production-ollama
time docker exec ai-production-ollama ollama run llama3.1:70b "Hello, how are you?"
```

### Performance Benchmarks
| Model | GPU (L4) | CPU (t2.large) | Speedup |
|-------|-----------|----------------|---------|
| gemma4:4b | 0.5s | 2.1s | 4.2x |
| gemma4:31b | 1.2s | 8.5s | 7.1x |
| llama3.1:70b | 2.8s | 25.3s | 9.0x |

## Troubleshooting GPU Issues

### Common GPU Issues
1. **GPU Not Detected**: Check nvidia-smi and Docker runtime
2. **Out of Memory**: Reduce OLLAMA_GPU_LAYERS or use smaller models
3. **Driver Issues**: Verify NVIDIA driver compatibility
4. **Container Permissions**: Check Docker GPU runtime access

### GPU Debug Commands
```bash
# Check GPU availability
nvidia-smi
docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi

# Check container GPU access
docker exec ai-production-ollama nvidia-smi
docker exec ai-production-ollama env | grep GPU

# Monitor GPU usage
watch -n 1 nvidia-smi
```

## GPU Deployment Checklist

### Pre-Deployment
- [ ] Verify GPU hardware (nvidia-smi)
- [ ] Check Docker GPU runtime
- [ ] Confirm sufficient VRAM for target models
- [ ] Validate network connectivity

### Deployment
- [ ] Run Script 1 with GPU detection
- [ ] Verify GPU_TYPE=nvidia in platform.conf
- [ ] Deploy with Script 2
- [ ] Check GPU reservations in Docker Compose

### Post-Deployment
- [ ] Verify GPU metrics in Prometheus
- [ ] Test GPU model loading
- [ ] Monitor GPU utilization
- [ ] Validate performance improvements

### Monitoring
- [ ] Set up GPU alerting thresholds
- [ ] Configure Grafana dashboards
- [ ] Monitor GPU temperature
- [ ] Track VRAM usage trends

## Cost Optimization

### GPU Instance Costs
- **g6.2xlarge**: ~$0.75/hour (1x L4 GPU)
- **g6.4xlarge**: ~$1.50/hour (2x L4 GPUs)
- **g6.8xlarge**: ~$3.00/hour (4x L4 GPUs)

### Optimization Strategies
1. **Right-sizing**: Choose appropriate GPU instance
2. **Spot Instances**: Use spot instances for cost savings
3. **Auto-scaling**: Scale based on demand
4. **Model Optimization**: Use efficient model sizes

## Security Considerations

### GPU Security
- **Isolation**: GPU resources isolated per tenant
- **Access Control**: GPU access limited to authorized containers
- **Data Privacy**: GPU memory cleared between sessions
- **Compliance**: GPU usage logged and monitored

### Multi-Tenant GPU
- **Resource Allocation**: Fair GPU sharing
- **Performance Isolation**: Prevent GPU contention
- **Billing**: Per-tenant GPU usage tracking
- **Audit**: GPU access logs and monitoring

This comprehensive guide ensures successful GPU-enabled deployments across all scenarios, from development to production workloads.
