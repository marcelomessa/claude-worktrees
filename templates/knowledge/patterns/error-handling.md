---
title: Error Handling Pattern
type: pattern
category: patterns
keywords: [error, exception, try, catch, handling, fallback]
---

# Error Handling Pattern

## Principle

Always handle errors explicitly. Never silence errors without logging.

## JavaScript/TypeScript

```typescript
// Good: explicit handling
try {
  const result = await riskyOperation();
  return result;
} catch (error) {
  console.error('[Context] Operation failed:', error.message);
  // Re-throw with context or return fallback
  throw new Error(`Operation failed: ${error.message}`);
}

// Bad: silencing error
try {
  await riskyOperation();
} catch (e) {
  // Never do this!
}
```

## Bash

```bash
# Good: set -e + specific handling
set -e

operation || {
  echo "Error: operation failed" >&2
  exit 1
}

# With cleanup
cleanup() {
  rm -f "$TEMP_FILE"
}
trap cleanup EXIT
```

## When to use fallbacks

1. Non-critical operations (cache miss → fetch)
2. Graceful degradation (feature disabled)
3. Optional configuration (use defaults)

## When to propagate errors

1. Critical operations (corrupted data)
2. Input validation (user error)
3. Mandatory dependencies
