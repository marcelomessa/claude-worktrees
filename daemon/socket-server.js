/**
 * Socket Server - Unix Socket handler com protocolo JSON-RPC
 */

const net = require('net');
const fs = require('fs');

class SocketServer {
  constructor(socketPath, stateManager, pubsub, voting, knowledgeManager = null) {
    this.socketPath = socketPath;
    this.stateManager = stateManager;
    this.pubsub = pubsub;
    this.voting = voting;
    this.knowledgeManager = knowledgeManager;
    this.server = null;
    this.clients = new Map(); // socket -> clientInfo
  }

  start() {
    // Remover socket antigo se existir
    if (fs.existsSync(this.socketPath)) {
      fs.unlinkSync(this.socketPath);
    }

    this.server = net.createServer((socket) => {
      this.handleConnection(socket);
    });

    this.server.listen(this.socketPath, () => {
      // Definir permissões do socket
      fs.chmodSync(this.socketPath, 0o777);
      console.log(`[SocketServer] Listening on ${this.socketPath}`);
    });

    this.server.on('error', (err) => {
      console.error('[SocketServer] Server error:', err.message);
    });

    return this;
  }

  handleConnection(socket) {
    const clientId = `client-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    let buffer = '';

    this.clients.set(socket, {
      id: clientId,
      connectedAt: new Date().toISOString(),
      workerId: null
    });

    console.log(`[SocketServer] New connection: ${clientId}`);

    socket.on('data', (data) => {
      buffer += data.toString();

      // Processar mensagens completas (delimitadas por newline)
      const lines = buffer.split('\n');
      buffer = lines.pop(); // Manter fragmento incompleto

      for (const line of lines) {
        if (line.trim()) {
          this.handleMessage(socket, line.trim());
        }
      }
    });

    socket.on('close', () => {
      const clientInfo = this.clients.get(socket);
      if (clientInfo) {
        console.log(`[SocketServer] Connection closed: ${clientInfo.workerId || clientId}`);

        if (clientInfo.workerId) {
          this.stateManager.unregisterWorker(clientInfo.workerId);
          this.pubsub.unsubscribeAll(clientInfo.workerId);
          this.pubsub.publish('worker.disconnected', { workerId: clientInfo.workerId });
        }

        this.clients.delete(socket);
      }
    });

    socket.on('error', (err) => {
      console.error(`[SocketServer] Socket error:`, err.message);
    });
  }

  handleMessage(socket, message) {
    let request;
    try {
      request = JSON.parse(message);
    } catch (e) {
      this.sendResponse(socket, { error: 'Invalid JSON' });
      return;
    }

    const { method, params, id } = request;
    const clientInfo = this.clients.get(socket);

    console.log(`[SocketServer] ${clientInfo.workerId || 'unknown'} -> ${method}`);

    let result;
    let error;

    try {
      switch (method) {
        // === Worker Management ===
        case 'register':
          result = this.handleRegister(socket, params);
          break;

        case 'heartbeat':
          result = this.handleHeartbeat(socket);
          break;

        case 'unregister':
          result = this.handleUnregister(socket);
          break;

        // === State ===
        case 'get_state':
          result = this.stateManager.get(params?.key);
          break;

        case 'set_state':
          result = this.stateManager.set(params.key, params.value);
          break;

        // === Tasks ===
        case 'add_task':
          result = this.stateManager.addTask(params);
          this.pubsub.publish('task.created', result, clientInfo.workerId);
          break;

        case 'update_task':
          result = this.stateManager.updateTask(params.taskId, params.updates);
          if (result) {
            this.pubsub.publish('task.progress', result, clientInfo.workerId);
          }
          break;

        case 'complete_task':
          result = this.stateManager.completeTask(params.taskId, params.summary);
          if (result) {
            this.pubsub.publish('task.completed', result, clientInfo.workerId);
          }
          break;

        // === Findings ===
        case 'add_finding':
          result = this.stateManager.addFinding(params);
          this.pubsub.publish('finding.reported', result, clientInfo.workerId);
          break;

        // === Blockers ===
        case 'add_blocker':
          result = this.stateManager.addBlocker(params);
          this.pubsub.publish('blocker.added', result, clientInfo.workerId);
          break;

        // === PubSub ===
        case 'subscribe':
          for (const topic of params.topics || [params.topic]) {
            this.pubsub.subscribe(clientInfo.workerId, topic, (msg) => {
              this.sendEvent(socket, msg);
            });
          }
          result = { subscribed: params.topics || [params.topic] };
          break;

        case 'unsubscribe':
          for (const topic of params.topics || [params.topic]) {
            this.pubsub.unsubscribe(clientInfo.workerId, topic);
          }
          result = { unsubscribed: params.topics || [params.topic] };
          break;

        case 'publish':
          const delivered = this.pubsub.publish(params.topic, params.data, clientInfo.workerId);
          result = { delivered };
          break;

        case 'broadcast':
          // Persistir broadcast no histórico de mensagens
          this.stateManager.addMessage(
            clientInfo.workerId || 'anonymous',
            null, // broadcast = to everyone
            JSON.stringify(params.data),
            'broadcast'
          );
          const broadcastDelivered = this.pubsub.broadcast(params.data, clientInfo.workerId);
          result = { delivered: broadcastDelivered, persisted: true };
          break;

        case 'send_direct':
          result = this.pubsub.sendDirect(params.to, params.data, clientInfo.workerId);
          break;

        // === Voting ===
        case 'create_vote':
          result = this.voting.createVote(
            clientInfo.workerId,
            params.decision,
            params.options,
            params.timeout,
            params.quorum
          );
          break;

        case 'cast_vote':
          result = this.voting.castVote(params.voteId, clientInfo.workerId, params.option);
          break;

        case 'get_vote_status':
          result = this.voting.getVoteStatus(params.voteId);
          break;

        case 'get_active_votes':
          result = this.voting.getActiveVotes();
          break;

        // === Messages ===
        case 'send_message':
          result = this.stateManager.addMessage(
            clientInfo.workerId,
            params.to || null,
            params.content,
            params.type || 'info'
          );
          break;

        case 'get_messages':
          result = this.stateManager.getMessages(clientInfo.workerId, params?.since);
          break;

        // === Info ===
        case 'get_workers':
          result = this.stateManager.getActiveWorkers();
          break;

        case 'get_stats':
          result = {
            workers: this.stateManager.getActiveWorkers().length,
            pubsub: this.pubsub.getStats(),
            activeVotes: this.voting.getActiveVotes().length
          };
          break;

        case 'ping':
          result = 'pong';
          break;

        // === Knowledge Base ===
        case 'kb_query':
          if (this.knowledgeManager) {
            result = this.knowledgeManager.query(params);
          } else {
            error = 'KnowledgeManager not initialized';
          }
          break;

        case 'kb_list':
          if (this.knowledgeManager) {
            result = this.knowledgeManager.list(params?.category);
          } else {
            error = 'KnowledgeManager not initialized';
          }
          break;

        case 'kb_get':
          if (this.knowledgeManager) {
            result = this.knowledgeManager.get(params.id);
          } else {
            error = 'KnowledgeManager not initialized';
          }
          break;

        case 'kb_add':
          if (!this.knowledgeManager) {
            error = 'KnowledgeManager not initialized';
          } else if (clientInfo.workerId !== 'coordinator') {
            error = 'kb_add: apenas coordinator pode adicionar';
          } else {
            result = this.knowledgeManager.add(params);
            if (result.success) {
              this.pubsub.publish('kb.added', result.entry, clientInfo.workerId);
            }
          }
          break;

        case 'kb_update':
          if (!this.knowledgeManager) {
            error = 'KnowledgeManager not initialized';
          } else if (clientInfo.workerId !== 'coordinator') {
            error = 'kb_update: apenas coordinator pode atualizar';
          } else {
            result = this.knowledgeManager.update(params.id, params.updates);
            if (result.success) {
              this.pubsub.publish('kb.updated', result.entry, clientInfo.workerId);
            }
          }
          break;

        case 'kb_delete':
          if (!this.knowledgeManager) {
            error = 'KnowledgeManager not initialized';
          } else if (clientInfo.workerId !== 'coordinator') {
            error = 'kb_delete: apenas coordinator pode remover';
          } else {
            result = this.knowledgeManager.delete(params.id);
            if (result.success) {
              this.pubsub.publish('kb.deleted', { id: params.id }, clientInfo.workerId);
            }
          }
          break;

        case 'kb_learn':
          if (!this.knowledgeManager) {
            error = 'KnowledgeManager not initialized';
          } else if (clientInfo.workerId !== 'coordinator') {
            error = 'kb_learn: apenas coordinator pode salvar padrões';
          } else {
            result = this.knowledgeManager.learn(params);
            if (result.success) {
              this.pubsub.publish('kb.learned', result.entry, clientInfo.workerId);
            }
          }
          break;

        // === Discoveries ===
        case 'discovery_add':
          if (this.knowledgeManager) {
            result = this.knowledgeManager.addDiscovery({
              ...params,
              workerId: clientInfo.workerId
            });
            if (result.success) {
              this.pubsub.publish('discovery.added', result.discovery, clientInfo.workerId);
            }
          } else {
            error = 'KnowledgeManager not initialized';
          }
          break;

        case 'discovery_list':
          if (this.knowledgeManager) {
            result = this.knowledgeManager.listDiscoveries(params?.since);
          } else {
            error = 'KnowledgeManager not initialized';
          }
          break;

        // === Safety Rules ===
        case 'safety_check':
          if (this.knowledgeManager) {
            result = this.knowledgeManager.checkSafety(params.command);
          } else {
            result = { allowed: true, rules: [] };
          }
          break;

        case 'safety_add':
          if (!this.knowledgeManager) {
            error = 'KnowledgeManager not initialized';
          } else if (clientInfo.workerId !== 'coordinator') {
            error = 'safety_add: apenas coordinator pode adicionar regras';
          } else {
            result = this.knowledgeManager.addSafetyRule(params);
            if (result.success) {
              this.pubsub.publish('safety.rule_added', result.rule, clientInfo.workerId);
            }
          }
          break;

        default:
          error = `Unknown method: ${method}`;
      }
    } catch (e) {
      error = e.message;
      console.error(`[SocketServer] Error handling ${method}:`, e);
    }

    this.sendResponse(socket, { id, result, error });
  }

  handleRegister(socket, params) {
    const clientInfo = this.clients.get(socket);
    const workerId = params.id || params.workerId;

    clientInfo.workerId = workerId;
    const worker = this.stateManager.registerWorker(workerId, params.capabilities || []);

    // Auto-subscribe em tópicos básicos
    const defaultTopics = ['broadcast', 'direct.message', 'vote.request', 'blocker.added'];
    for (const topic of defaultTopics) {
      this.pubsub.subscribe(workerId, topic, (msg) => {
        this.sendEvent(socket, msg);
      });
    }

    this.pubsub.publish('worker.registered', { workerId, capabilities: params.capabilities });

    return worker;
  }

  handleHeartbeat(socket) {
    const clientInfo = this.clients.get(socket);
    if (clientInfo.workerId) {
      return this.stateManager.heartbeat(clientInfo.workerId);
    }
    return false;
  }

  handleUnregister(socket) {
    const clientInfo = this.clients.get(socket);
    if (clientInfo.workerId) {
      this.stateManager.unregisterWorker(clientInfo.workerId);
      this.pubsub.unsubscribeAll(clientInfo.workerId);
      this.pubsub.publish('worker.disconnected', { workerId: clientInfo.workerId });
      clientInfo.workerId = null;
      return true;
    }
    return false;
  }

  sendResponse(socket, response) {
    try {
      socket.write(JSON.stringify(response) + '\n');
    } catch (e) {
      console.error('[SocketServer] Error sending response:', e.message);
    }
  }

  sendEvent(socket, event) {
    try {
      socket.write(JSON.stringify({ event: true, ...event }) + '\n');
    } catch (e) {
      console.error('[SocketServer] Error sending event:', e.message);
    }
  }

  stop() {
    if (this.server) {
      this.server.close();
      if (fs.existsSync(this.socketPath)) {
        fs.unlinkSync(this.socketPath);
      }
      console.log('[SocketServer] Stopped');
    }
  }
}

module.exports = SocketServer;
