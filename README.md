# AIPlatformAutomation

## 1. Purpose

AIPlatformAutomation provides a **fully automated, modular, self-hosted AI platform** designed to:

- Run **on-prem or in private cloud**
- Embed **private data locally**
- Share those embeddings across **multiple AI services**
- Combine **local LLMs** and **external LLM providers**
- Enforce **strict network separation**
- Be **reproducible, auditable, and extensible**

The platform is entirely driven by scripts and configuration files, not manual steps.

---

## 2. Core Objectives

- Deploy a **single integrated AI platform**, not isolated tools  
- Maintain a **shared private vector memory** usable by all services  
- Enable deterministic setup and deployment  
- Minimize the trust surface  
- Enforce clear operational boundaries  
- Support incremental extensibility without full redeployment  

---

## 3. Key Outcomes

After full execution, the platform provides:

- On-prem **vector embeddings of private data**  
- Multiple AI applications consuming the same embeddings  
- Centralized **LiteLLM routing**  
- Optional external LLM augmentation (OpenAI, OpenRouter, Google Gemini, Groq, etc.)  
- Secure public access for selected services  
- Private administrative access via **Tailscale**  
- Modular service lifecycle management  

---

## 4. Architectural Principles

1. **Separation of Concerns** – Cleanup, configuration, deployment, wiring, and extension are isolated  
2. **Network Segmentation** – Public access, private service traffic, and admin access are separated  
3. **Data Gravity** – Private data and embeddings remain local  
4. **Explicit Configuration** – All decisions are collected once and reused  
5. **Service Composability** – Each service is independently dockerized and replaceable  

---

## 5. Network Architecture (ASCII Diagram)
