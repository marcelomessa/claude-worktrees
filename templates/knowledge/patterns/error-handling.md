---
title: Error Handling Pattern
type: pattern
category: patterns
keywords: [error, exception, try, catch, handling, fallback]
---

# Error Handling Pattern

## Princípio

Sempre trate erros de forma explícita. Nunca silencie erros sem log.

## JavaScript/TypeScript

```typescript
// Bom: tratamento explícito
try {
  const result = await riskyOperation();
  return result;
} catch (error) {
  console.error('[Context] Operation failed:', error.message);
  // Re-throw com contexto ou return fallback
  throw new Error(`Operation failed: ${error.message}`);
}

// Ruim: silenciar erro
try {
  await riskyOperation();
} catch (e) {
  // Nunca faça isso!
}
```

## Bash

```bash
# Bom: set -e + tratamento específico
set -e

operation || {
  echo "Error: operation failed" >&2
  exit 1
}

# Com cleanup
cleanup() {
  rm -f "$TEMP_FILE"
}
trap cleanup EXIT
```

## Quando usar fallbacks

1. Operações não-críticas (cache miss → fetch)
2. Degradação graceful (feature desabilitada)
3. Configuração opcional (usar defaults)

## Quando propagar erro

1. Operações críticas (dados corrompidos)
2. Validação de input (user error)
3. Dependências obrigatórias
