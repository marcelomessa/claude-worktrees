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
# 1. SEMPRE fetch primeiro (atualiza referências)
git fetch origin

# 2. Review de mudanças do worker
git diff main..feature/worker-branch

# 3. Garantir que está na main
git checkout main

# 4. Merge com --no-ff (SEMPRE - preserva histórico)
git merge feature/worker-branch --no-ff -m "Merge feature/X: description"

# 5. Push (após review e testes)
git push origin main
```

### Worktree Merge - Ordem Correta

1. Worker faz commit na feature branch (worktree separada)
2. Worker avisa coordinator: `wt-msg send coordinator "done"`
3. Coordinator faz `git fetch origin`
4. Coordinator revisa: `git diff main..feature/branch`
5. Coordinator merge: `git merge feature/branch --no-ff`
6. Coordinator push: `git push origin main`
7. Coordinator notifica worker para próxima task

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
