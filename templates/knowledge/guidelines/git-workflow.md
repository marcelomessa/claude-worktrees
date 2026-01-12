---
title: Git Workflow para Multi-Agent
type: guideline
category: guidelines
keywords: [git, commit, branch, merge, workflow, multi-agent]
---

# Git Workflow para Multi-Agent

## Princípios

1. **Workers**: trabalham em suas branches isoladas
2. **Coordinator**: único que faz merge/push para main
3. **Comunicação**: sempre avisar antes de operações que afetam outros

## Workflow por Role

### Worker

```bash
# PODE fazer
git add <arquivos específicos>
git commit -m "feat: ..."
git log
git status
git diff

# NÃO PODE (requer coordinator)
git push                    # bloqueado
git merge                   # bloqueado
git rebase                  # bloqueado
git checkout main/master    # bloqueado
```

### Coordinator

```bash
# Review de mudanças do worker
git diff worker-branch

# Merge quando aprovado
git checkout main
git merge worker-branch --no-ff

# Push (após review)
git push origin main
```

## Antes de Commit

1. Verifique mudanças: `git diff`
2. Adicione arquivos específicos: `git add file1 file2`
3. Nunca use: `git add -A` ou `git add .`

## Mensagens de Commit

```
<type>(<scope>): <description>

Types: feat, fix, docs, style, refactor, test, chore
Scope: opcional, área afetada

Exemplos:
feat(auth): add login with OAuth
fix(api): handle rate limit errors
```

## Recuperação Segura

```bash
# Ver versão anterior SEM perder atual
git show HEAD~1:path/to/file

# Comparar com versão anterior
git diff HEAD~1 -- path/to/file

# Salvar trabalho atual antes de qualquer operação
git stash push -m "backup before risky operation"
```

## NUNCA Fazer

- `git checkout -- .` (perde mudanças)
- `git reset --hard` (perde tudo)
- `git clean -fd` (remove arquivos)
- Push sem review do coordinator
