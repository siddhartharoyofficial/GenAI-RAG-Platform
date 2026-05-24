# Project Description

Pick the length that fits where you're posting it.

---

## One line  (GitHub repo "About" field, portfolio bio)

A production grade GenAI RAG platform on Google Cloud that uses semantic caching and multi model routing to deliver fast, accurate answers at scale.

---

## Short  (LinkedIn project section, ~280 chars)

A reference architecture for a Gen AI assistant that stays fast and accurate even under heavy traffic. Built on Google Cloud (Vertex AI, AlloyDB, Memorystore, GKE) and deployed end to end with Terraform. Solves the two biggest problems in production RAG: slow responses and hallucinations.

---

## Medium  (READ ME intro, blog summary)

GenAI RAG Platform is a production grade Retrieval Augmented Generation system designed for real workloads, not demos.

Most AI assistants today are either fast but unreliable, or accurate but slow. This project fixes that with three ideas working together. A semantic cache that answers repeat questions in under 10 milliseconds. An intent router that sends simple questions to a cheap model and complex ones to a frontier model. A hybrid search layer that combines semantic and keyword matching so the AI gets the right context every time.

The whole system runs on Google Cloud (Vertex AI, AlloyDB with pgvector, Memorystore for Redis, GKE Autopilot) and is deployed entirely through Terraform. It cuts cost per query by around 60 percent and keeps time to first token under 200 milliseconds for 95 percent of users.

---

## Long  (cover letter, detailed pitch, conference abstract)

GenAI RAG Platform is a reference implementation of a high accuracy, low latency Retrieval Augmented Generation system on Google Cloud. It was built for the Hack2Skill System Design Thinking Challenge to answer one question: how do you design a Gen AI assistant that holds up under real production traffic, not just on a single happy path demo?

Most public RAG examples fall apart under two pressures. Tail latency balloons past 8 seconds during traffic spikes because every query runs through the full retrieve, rerank, generate pipeline. And hallucinations appear when retrieval returns chunks that are semantically close but factually wrong, with no signal for the model to catch the mismatch.

This platform fixes both. A semantic cache built on Memorystore Redis intercepts paraphrases of past questions and returns cached answers in under 10 ms. An intent router built on Gemini 2.5 Flash classifies each new query and dispatches it down the cheapest path that can still satisfy it. A hybrid retrieval layer in AlloyDB combines pgvector semantic search with Postgres full text search, then fuses both rankings using Reciprocal Rank Fusion. A Vertex AI Endpoint running Cohere Rerank 3 trims the top 50 candidates to a precise top 5 before the synthesis step. Synthesis itself routes between Gemini 2.5 Flash for most traffic and Claude 3.5 Sonnet via Vertex AI Model Garden for the hardest 20 percent.

Everything is deployed through Terraform. Three environments (dev, staging, prod) share the same module composition with different sizing. GitHub Actions handles plan and apply through Workload Identity Federation. The result is a platform that delivers sub second p95 latency, lifts retrieval recall by 15 to 25 percent through hybrid search, and cuts cost per query by roughly 60 percent compared to a frontier model only approach.

Source code, infrastructure, runbooks, and Ragas evaluation harness are all included.

---

## Tagline options  (pick one for the top of the GitHub README, LinkedIn header)

- Fast and accurate Gen AI at production scale, on Google Cloud
- The LLM is the most expensive part of the system. Treat it like one.
- Production grade RAG that survives Black Friday traffic
- Hybrid cache and multi model routing for real world Gen AI
