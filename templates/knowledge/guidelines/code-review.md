---
title: Code Review Guidelines
type: guideline
category: guidelines
keywords: [review, code, quality, standards, pr, pull-request]
---

# Code Review Guidelines

## Antes de Pedir Review

1. Código compila/roda sem erros
2. Testes passam (se existirem)
3. Commit message clara
4. Mudanças focadas (uma feature/fix por vez)

## Checklist de Review

### Funcionalidade
- [ ] Resolve o problema proposto
- [ ] Não quebra features existentes
- [ ] Edge cases tratados

### Segurança
- [ ] Input validation (especialmente user input)
- [ ] Sem secrets hardcoded
- [ ] Sem SQL injection / XSS vulnerabilities
- [ ] Permissões verificadas

### Qualidade
- [ ] Código legível e auto-documentado
- [ ] Sem duplicação desnecessária
- [ ] Sem código morto / comentado
- [ ] Nomes significativos (variáveis, funções)

### Performance
- [ ] Sem N+1 queries
- [ ] Sem loops desnecessários
- [ ] Recursos liberados (files, connections)

## Comunicação Worker → Coordinator

```bash
# Avisar que está pronto para review
wt-msg send coordinator "Branch frontend-auth pronta para review"

# Detalhes do que foi feito
wt-msg send coordinator "Implementei login OAuth. Ver commits em frontend-auth"
```

## Comunicação Coordinator → Worker

```bash
# Aprovar
wt-msg send frontend "Aprovado! Farei merge agora"

# Solicitar mudanças
wt-msg send frontend "Por favor: 1) Adicionar validação email, 2) Tratar erro 401"
```

## Merge Checklist

- [ ] CI passou (se disponível)
- [ ] Conflitos resolvidos
- [ ] Changelog atualizado (se aplicável)
- [ ] Branch pode ser deletada após merge
