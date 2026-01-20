# Roteiro de Demo - CWT (Claude Worktrees)

**Duração estimada:** 5-7 minutos

---

## Preparação (antes de gravar)

```bash
# Limpar ambiente anterior
cd /tmp && rm -rf cwt-demo
tmux kill-session -t cwt-my-project 2>/dev/null

# Ter um repo para clonar (ex: expressjs/express ou seu próprio)
```

---

## PARTE 1: Setup Inicial (1 min)

### 1.1 Criar projeto

```bash
cd /tmp
mkdir cwt-demo && cd cwt-demo

# Clonar um repo de exemplo
git clone https://github.com/expressjs/express.git main --depth 1

# Inicializar CWT
cwt init --repo main --name my-project
```

**Narração:** "CWT cria uma estrutura de projeto com configuração isolada em .cwt/"

### 1.2 Mostrar estrutura

```bash
ls -la
cat .cwt/config.json
```

---

## PARTE 2: Criar Workers (1 min)

### 2.1 Criar worktrees

```bash
wt-init backend frontend
```

**Narração:** "Cada worker recebe seu próprio diretório e branch isolados"

### 2.2 Mostrar resultado

```bash
ls -la
git -C main worktree list
```

---

## PARTE 3: Iniciar Sessão Multi-Agente (1 min)

### 3.1 Iniciar CWT

```bash
cwt
```

**Narração:** "CWT inicia uma sessão tmux com coordinator e workers em janelas separadas"

### 3.2 Navegar entre janelas

- `Ctrl+B 0` - Coordinator
- `Ctrl+B 1` - Backend worker
- `Ctrl+B 2` - Frontend worker

**Narração:** "Cada agente Claude trabalha de forma independente em seu workspace"

---

## PARTE 4: Comunicação entre Agentes (1 min)

### 4.1 Enviar tarefa (do coordinator)

```bash
wt-task backend "Criar endpoint GET /api/users"
wt-task frontend "Criar componente UserList"
```

### 4.2 Ver status de mensagens

```bash
wt-msg status
```

### 4.3 Worker responde (mudar para janela do worker)

```bash
# Ctrl+B 1 (ir para backend)
wt-msg read
wt-msg send coordinator "Endpoint criado em routes/users.js"
```

---

## PARTE 5: Knowledge Base (30s)

### 5.1 Consultar padrões

```bash
wt-kb query "error handling"
wt-kb list
```

**Narração:** "Workers consultam a base de conhecimento antes de perguntar ao coordinator"

---

## PARTE 6: Budget Control (30s)

### 6.1 Configurar limite

```bash
cwt budget --limit 10 --period daily
```

### 6.2 Ver status

```bash
wt-billing
```

**Narração:** "Controle de gastos por projeto com limites configuráveis"

---

## PARTE 7: Help & Settings (30s)

### 7.1 Abrir popup de ajuda

- Pressionar `Ctrl+B ?`

**Narração:** "O popup mostra atalhos, status do budget e permite configuração"

- Pressionar `q` para fechar

---

## PARTE 8: Segurança (30s)

### 8.1 Mostrar que worker não pode fazer push

```bash
# Na janela do worker
git push
# Vai ser bloqueado pelo bash-validator
```

**Narração:** "Workers são impedidos de operações destrutivas - apenas o coordinator pode fazer push, merge e deploy"

---

## PARTE 9: Encerrar (15s)

### 9.1 Detach da sessão

- `Ctrl+B d`

**Narração:** "A sessão continua rodando em background"

### 9.2 Mostrar que sessão existe

```bash
cwt --list
```

### 9.3 Reconectar

```bash
cwt
```

### 9.4 Encerrar de vez

```bash
cwt --kill
```

---

## Pontos-Chave para Enfatizar

1. **Isolamento** - Cada worker tem seu próprio diretório e branch
2. **Coordenação** - Comunicação estruturada via mensagens
3. **Segurança** - Hooks previnem operações perigosas
4. **Budget** - Controle de custos em tempo real
5. **Knowledge Base** - Padrões compartilhados entre agentes
6. **Skills** - Claude já sabe seu papel (coordinator/worker)

---

## Comandos Rápidos de Referência

| Comando | Descrição |
|---------|-----------|
| `cwt init --repo X --name Y` | Inicializar projeto |
| `wt-init worker1 worker2` | Criar worktrees |
| `cwt` | Iniciar/reconectar sessão |
| `cwt --solo` | Apenas coordinator |
| `cwt --kill` | Encerrar sessão |
| `wt-task worker "msg"` | Enviar tarefa |
| `wt-msg send to "msg"` | Enviar mensagem |
| `wt-msg status` | Ver mensagens |
| `wt-kb query "X"` | Buscar na KB |
| `cwt budget --limit X` | Definir limite |
| `Ctrl+B ?` | Help popup |
| `Ctrl+B 0-9` | Trocar janela |
| `Ctrl+B d` | Detach |
