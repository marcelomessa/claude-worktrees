# Proposta: Coordenacao Multi-Projeto para CWT

**Data:** 2025-12-31
**Status:** ✅ IMPLEMENTADO (2026-01-01)

> Esta proposta foi implementada. Veja README.md para documentação atualizada.

---

## Problema Atual

### 1. Estado Global

O CWT usa estado global em `/tmp/` que mistura todos os projetos:

```
/tmp/
├── cwt-workers-list.txt      # Lista global de workers
├── claude-wt-state.json      # Mensagens de TODOS os projetos
└── claude-wt-config.json     # Config da sessao
```

### 2. Estrutura de Diretorios Confusa

Worktrees ficam como irmaos do projeto, dificultando administracao:

```
~/repos/                      # ATUAL - tudo misturado
├── my-project/               # main
├── workspace-frontend/       # worktree (irmao do projeto!)
├── workspace-backend/        # worktree
├── other-project/            # outro projeto
└── workspace-security/       # qual projeto pertence? confuso!
```

**Problemas:**
1. Sessao tmux `cwt` e unica - conflita entre projetos
2. Mensagens de um projeto vazam para outros
3. Workers de projetos diferentes se veem
4. Worktrees espalhados dificultam administracao
5. Nao suporta 3+ frentes simultaneas

---

## Use Cases do Usuario

1. **Multi-frente simultaneo:**
   - 3+ projetos abertos em paralelo
   - Cada um com seu contexto e coordenacao

2. **Multi-repo por projeto:**
   - Documentacao: criar docs em 5 repos de API
   - Nao sao worktrees git - sao repos diferentes!

3. **Isolamento:**
   - Broadcasts nao vazam entre projetos
   - Cada projeto tem seu coordenador

4. **Organizacao:**
   - Cada projeto auto-contido em sua pasta
   - Facil de ver o que pertence a cada projeto

---

## Arquitetura Proposta

### 1. Projeto como Pasta Container

**Mudanca fundamental**: O projeto e uma pasta que CONTEM os repos/worktrees:

```
~/projects/azion-workspace/   # PASTA DO PROJETO (nao e um repo!)
├── .cwt/                     # Config/estado do CWT
│   ├── state.json            # Mensagens deste projeto
│   ├── workers.txt           # Workers ativos
│   ├── config.json           # Config do projeto
│   └── session.txt           # Nome da sessao tmux
│
├── main/                     # ← COORDENADOR (window 0)
│   ├── .git/                 #   Git completo - pode fazer merge/deploy
│   └── src/
│
├── feature-security/         # ← Worker 1 (worktree de main)
│   ├── .git -> ../main/.git
│   └── src/
│
├── feature-ui/               # ← Worker 2 (worktree de main)
│   ├── .git -> ../main/.git
│   └── src/
│
└── docs/                     # ← Worker 3 (outro repo)
    ├── .git/
    └── content/
```

**Coordenador em `main/`:**
- Tem git completo (nao e worktree)
- Pode fazer `git merge feature/security`
- Pode fazer `azion deploy`
- Acessa `.cwt/` via `../.cwt/`

### Comparacao

```
ANTES (confuso)                    DEPOIS (organizado)
──────────────                     ──────────────────
~/repos/                           ~/projects/azion-workspace/
├── my-project/                    ├── .cwt/
├── workspace-frontend/  ──────►   ├── main/
├── workspace-backend/             ├── feature-security/
├── other-project/                 ├── feature-ui/
└── workspace-security/            └── docs/

                                   ~/projects/api-docs/
                                   ├── .cwt/
                                   ├── api-edge/
                                   ├── api-storage/
                                   └── api-security/
```

### 2. Sessao Tmux com Nome do Projeto

```bash
# ANTES: Nome fixo
SESSION_NAME="cwt"

# DEPOIS: Nome baseado no projeto
PROJECT_NAME=$(basename "$PROJECT_DIR")
SESSION_NAME="cwt-$PROJECT_NAME"

# Exemplo:
# cwt-workspace-ui    (projeto 1)
# cwt-api-docs        (projeto 2)
# cwt-mcp-integration (projeto 3)
```

### 3. Mudancas no wt-msg

```bash
# ANTES:
STATE_FILE="/tmp/claude-wt-state.json"

# DEPOIS:
get_state_file() {
  # 1. Tentar .cwt/ local
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.cwt" ]]; then
      echo "$dir/.cwt/state.json"
      return
    fi
    dir=$(dirname "$dir")
  done

  # 2. Fallback para /tmp/ (compatibilidade)
  echo "/tmp/claude-wt-state.json"
}

STATE_FILE=$(get_state_file)
```

### 4. Mudancas no tmux-launcher.sh

```bash
# Linha 17-18 ATUAL:
LOG_DIR="${CWT_LOG_DIR:-$HOME/repos/terminal_logs}"
CWT_CONFIG_DIR="$(cd "$(dirname "$0")/../config" && pwd)"

# ADICIONAR:
PROJECT_NAME=$(basename "$PROJECT_DIR")
SESSION_NAME="cwt-${PROJECT_NAME}"
CWT_STATE_DIR="$PROJECT_DIR/.cwt"

# Inicializar .cwt/
init_cwt_state() {
  mkdir -p "$CWT_STATE_DIR"
  echo '{"workers":{},"messages":[]}' > "$CWT_STATE_DIR/state.json"
  echo "$SESSION_NAME" > "$CWT_STATE_DIR/session.txt"
  cat > "$CWT_STATE_DIR/config.json" << EOF
{
  "project": "$PROJECT_NAME",
  "repo": "$PROJECT_DIR",
  "base": "$CURRENT_BRANCH",
  "workers": $(printf '%s\n' "${WORKSPACES[@]}" | jq -R . | jq -s .)
}
EOF
}
```

### 5. Config de Projeto (Opcional)

Para projetos com multiplos repos (nao worktrees):

```json
// .cwt/project.json (opcional)
{
  "name": "api-documentation",
  "description": "Multi-repo API docs project",

  "repos": [
    {
      "name": "api-edge",
      "path": "../api-edge",
      "type": "separate"
    },
    {
      "name": "api-storage",
      "path": "../api-storage",
      "type": "separate"
    }
  ],

  "workers": {
    "edge-docs": {"repo": "api-edge"},
    "storage-docs": {"repo": "api-storage"}
  }
}
```

---

## Fluxo de Uso

### 1. Criar Novo Projeto

```bash
# Criar pasta do projeto
mkdir -p ~/projects/azion-workspace
cd ~/projects/azion-workspace

# Inicializar CWT (cria .cwt/)
cwt init --name "azion-workspace"

# Clonar repo principal
git clone git@github.com:user/workspace.git main
cd main

# Criar worktrees DENTRO da pasta do projeto
git worktree add ../feature-security -b feature/security
git worktree add ../feature-ui -b feature/ui

# (Opcional) Clonar repo separado
cd ..
git clone git@github.com:user/workspace-docs.git docs
```

### 2. Iniciar Sessao

```bash
cd ~/projects/azion-workspace

# CWT detecta .cwt/ e usa configuracao local
cwt feature-security feature-ui docs

# Layout criado:
#   Window 0: coordinator  → main/
#   Window 1: feature-security → feature-security/
#   Window 2: feature-ui → feature-ui/
#   Window 3: docs → docs/
#   Window 4: monitor

# Sessao: cwt-azion-workspace
# Estado: .cwt/state.json
```

### 3. Trabalhar em Multiplos Projetos

```bash
# Terminal 1: Projeto Azion
cd ~/projects/azion-workspace && cwt

# Terminal 2: Projeto API Docs
cd ~/projects/api-docs && cwt

# Terminal 3: Projeto MCP
cd ~/projects/mcp-integration && cwt

# Cada um tem sua sessao tmux isolada!
```

---

## Implementacao Incremental

### Fase 1: Comando `cwt init`

Novo comando para criar estrutura de projeto:

```bash
# lib/wt-init (ou bin/cwt-init)

cwt_init() {
  local project_name="${1:-$(basename "$PWD")}"

  mkdir -p .cwt

  # Criar config inicial
  cat > .cwt/config.json << EOF
{
  "name": "$project_name",
  "created": "$(date -Iseconds)",
  "type": "project"
}
EOF

  # Criar state vazio
  echo '{"workers":{},"messages":[]}' > .cwt/state.json

  echo "Projeto '$project_name' inicializado"
  echo "Agora clone seus repos nesta pasta e use 'cwt' para iniciar"
}
```

### Fase 2: Isolamento de Estado

**Mudancas minimas para isolamento:**

1. `tmux-launcher.sh`:
   - Detectar `.cwt/` subindo arvore
   - Sessao nomeada: `cwt-$PROJECT_NAME`
   - Usar `.cwt/state.json` local

2. `wt-msg`:
   - Detectar `.cwt/state.json` subindo arvore
   - Fallback para `/tmp/` (compatibilidade)

3. `cwt`:
   - Novo subcomando `init`
   - Listar sessoes por projeto
   - Reconectar a sessao correta

**Arquivos a modificar:**
- `bin/cwt` (~30 linhas - adicionar init)
- `bin/tmux-launcher.sh` (~20 linhas)
- `lib/wt-msg` (~10 linhas)

### Fase 3: Deteccao de Repos e Coordinator

```bash
# tmux-launcher.sh

# Detectar diretorio do coordenador (main/)
detect_coordinator_dir() {
  # 1. Configurado em .cwt/config.json
  if [[ -f ".cwt/config.json" ]]; then
    local coord=$(jq -r '.coordinator // empty' .cwt/config.json)
    [[ -n "$coord" && -d "$coord" ]] && echo "$coord" && return
  fi

  # 2. Pasta chamada "main"
  [[ -d "main" ]] && echo "main" && return

  # 3. Primeira pasta com .git/ completo (nao worktree)
  for dir in */; do
    if [[ -d "$dir/.git" ]]; then
      echo "${dir%/}"
      return
    fi
  done
}

# Detectar workers (worktrees + repos separados)
detect_workers() {
  local coord_dir=$(detect_coordinator_dir)

  for dir in */; do
    local name="${dir%/}"

    # Pular coordenador e .cwt
    [[ "$name" == "$coord_dir" || "$name" == ".cwt" ]] && continue

    # Verificar se e repo ou worktree
    if [[ -d "$dir/.git" ]] || [[ -f "$dir/.git" ]]; then
      echo "$name"
    fi
  done
}
```

Com isso, o launcher:
1. Detecta `main/` como coordenador (ou outro configurado)
2. Detecta demais pastas com `.git` como workers
3. Worktrees (`.git` e arquivo) e repos (`.git` e pasta) sao tratados igual

### Fase 4: Dashboard Unificado

Para ver todos os projetos ativos:

```bash
cwt --list-all

# Output:
# ═══════════════════════════════════════
# PROJETOS CWT ATIVOS
# ═══════════════════════════════════════
# cwt-azion-workspace  3 workers  (security, ui, docs)
# cwt-api-docs         5 workers  (edge, storage, ...)
# cwt-mcp-integration  2 workers  (core, alerts)
```

---

## Backward Compatibility

| Cenario | Comportamento |
|---------|---------------|
| Projeto sem `.cwt/` | Usa `/tmp/` como antes |
| Projeto com `.cwt/` | Usa estado local |
| Sessao `cwt` existente | Continua funcionando |
| Novos projetos | Criam `.cwt/` automaticamente |

---

## Resumo das Mudancas

### Estrutura

```
ANTES                              DEPOIS
─────                              ──────
~/repos/                           ~/projects/meu-projeto/
├── projeto/                       ├── .cwt/           # estado local
├── workspace-a/  (solto!)         ├── main/           # repo principal
├── workspace-b/  (qual projeto?)  ├── feature-a/      # worktree
└── outro-projeto/                 ├── feature-b/      # worktree
                                   └── docs/           # outro repo
```

### Estado

```
ANTES                          DEPOIS
─────                          ──────
/tmp/claude-wt-state.json      meu-projeto/.cwt/state.json
/tmp/cwt-workers-list.txt      meu-projeto/.cwt/workers.txt
SESSION_NAME="cwt"             SESSION_NAME="cwt-meu-projeto"
```

### Beneficios

| Aspecto | Antes | Depois |
|---------|-------|--------|
| Estrutura | Worktrees soltos como irmaos | Tudo dentro da pasta do projeto |
| Estado | Global em /tmp | Local em .cwt/ |
| Sessao tmux | Uma unica "cwt" | Uma por projeto |
| Multi-projeto | Conflitos de estado | Isolamento total |
| Multi-repo | Apenas worktrees | Worktrees + repos separados |

---

## Proximos Passos

1. [x] Implementar `cwt init` (criar .cwt/)
2. [x] Atualizar tmux-launcher.sh para detectar .cwt/
3. [x] Atualizar wt-msg para usar estado local
4. [x] Testar com 2-3 projetos simultaneos
5. [x] Documentar nova estrutura no README

---

*Proposta implementada | 2026-01-01*
