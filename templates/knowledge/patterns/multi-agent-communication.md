---
title: Multi-Agent Communication
type: pattern
category: patterns
keywords: [multi-agent, communication, coordinator, worker, message, broadcast]
---

# Multi-Agent Communication

## Hierarquia

```
coordinator (central)
    ├── worker-1 (frontend)
    ├── worker-2 (backend)
    └── worker-3 (docs)
```

## Quando Comunicar

### Worker → Coordinator

1. **Bloqueio**: não consegue prosseguir
2. **Decisão arquitetural**: afeta outros workers
3. **Review necessário**: código pronto para merge
4. **Descoberta importante**: info útil para outros

```bash
wt-msg send coordinator "BLOQUEIO: API /users retorna 404, preciso do endpoint"
wt-msg send coordinator "DECISÃO: usar Redux ou Context para state?"
wt-msg send coordinator "REVIEW: branch feature-x pronta"
```

### Coordinator → Worker

1. **Task assignment**: nova tarefa
2. **Resposta a bloqueio**: solução/orientação
3. **Broadcast**: info geral

```bash
wt-task backend "Implementar endpoint /api/users"
wt-msg send frontend "API está pronta: POST /api/auth/login"
wt-msg broadcast "Mudança de arquitetura: todos usem TypeScript strict"
```

### Worker → Worker

Geralmente via discoveries (evitar comunicação direta):

```bash
wt-kb discover "API rate limit" "API /search tem limit 100/min"
```

## Formato de Mensagens

### Bloqueio
```
BLOQUEIO: [descrição curta]
Contexto: [o que você tentou]
Preciso: [o que você precisa]
```

### Descoberta
```
DISCOVERY: [título]
[descrição]
Relevância: [quem deve saber]
```

### Task Completion
```
DONE: [task]
Arquivos: [lista de arquivos modificados]
Branch: [nome da branch]
```

## Anti-patterns

- Mensagens longas demais (resumir)
- Perguntar sem pesquisar primeiro (`wt-kb query`)
- Comunicação direta worker-worker para decisões (usar coordinator)
- Não reportar bloqueios (ficar travado silenciosamente)
