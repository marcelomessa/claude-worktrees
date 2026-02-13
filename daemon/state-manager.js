/**
 * State Manager - In-memory state management with persistence
 * Adapted for CWT multi-project
 */

const fs = require('fs');
const path = require('path');

class StateManager {
  constructor(stateFile, projectName = 'cwt-project') {
    this.stateFile = stateFile;
    this.projectName = projectName;
    this.state = this.loadState();
    this.dirty = false;

    // Auto-save every 30 seconds if there are changes
    this.saveInterval = setInterval(() => {
      if (this.dirty) {
        this.persist();
      }
    }, 30000);
  }

  loadState() {
    const defaults = {
      project: this.projectName,
      version: '2.0.0',
      lastUpdated: new Date().toISOString(),
      workers: {},
      workQueue: [],
      completedTasks: [],
      findings: [],
      blockers: [],
      messages: []
    };

    try {
      if (fs.existsSync(this.stateFile)) {
        const data = fs.readFileSync(this.stateFile, 'utf8');
        const loaded = JSON.parse(data);
        // Merge with defaults to ensure all fields exist
        return { ...defaults, ...loaded };
      }
    } catch (e) {
      console.error('[StateManager] Error loading state:', e.message);
    }

    return defaults;
  }

  persist() {
    try {
      this.state.lastUpdated = new Date().toISOString();
      const dir = path.dirname(this.stateFile);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
      fs.writeFileSync(this.stateFile, JSON.stringify(this.state, null, 2));
      this.dirty = false;
      console.log('[StateManager] State persisted');
    } catch (e) {
      console.error('[StateManager] Error persisting state:', e.message);
    }
  }

  // Get value by path (e.g.: "workers.worker-1.status")
  get(keyPath) {
    if (!keyPath) return this.state;

    const keys = keyPath.split('.');
    let value = this.state;

    for (const key of keys) {
      if (value === undefined || value === null) return undefined;
      value = value[key];
    }

    return value;
  }

  // Set value by path
  set(keyPath, value) {
    const keys = keyPath.split('.');
    const lastKey = keys.pop();
    let target = this.state;

    for (const key of keys) {
      if (!(key in target)) {
        target[key] = {};
      }
      target = target[key];
    }

    target[lastKey] = value;
    this.dirty = true;

    return true;
  }

  // Register worker
  registerWorker(workerId, capabilities = []) {
    this.state.workers[workerId] = {
      id: workerId,
      capabilities,
      status: 'active',
      registeredAt: new Date().toISOString(),
      lastHeartbeat: new Date().toISOString()
    };
    this.dirty = true;
    console.log(`[StateManager] Worker registered: ${workerId}`);
    return this.state.workers[workerId];
  }

  // Update heartbeat
  heartbeat(workerId) {
    if (this.state.workers[workerId]) {
      this.state.workers[workerId].lastHeartbeat = new Date().toISOString();
      this.state.workers[workerId].status = 'active';
      this.dirty = true;
      return true;
    }
    return false;
  }

  // Unregister worker
  unregisterWorker(workerId) {
    if (this.state.workers[workerId]) {
      this.state.workers[workerId].status = 'disconnected';
      this.state.workers[workerId].disconnectedAt = new Date().toISOString();
      this.dirty = true;
      return true;
    }
    return false;
  }

  // List active workers
  getActiveWorkers() {
    return Object.values(this.state.workers).filter(w => w.status === 'active');
  }

  // Add task to queue
  addTask(task) {
    task.id = task.id || `task-${Date.now()}`;
    task.createdAt = new Date().toISOString();
    task.status = task.status || 'pending';
    this.state.workQueue.push(task);
    this.dirty = true;
    return task;
  }

  // Update task
  updateTask(taskId, updates) {
    const task = this.state.workQueue.find(t => t.id === taskId);
    if (task) {
      Object.assign(task, updates, { updatedAt: new Date().toISOString() });
      this.dirty = true;
      return task;
    }
    return null;
  }

  // Complete task
  completeTask(taskId, summary) {
    const taskIndex = this.state.workQueue.findIndex(t => t.id === taskId);
    if (taskIndex >= 0) {
      const task = this.state.workQueue.splice(taskIndex, 1)[0];
      task.status = 'completed';
      task.completedAt = new Date().toISOString();
      task.summary = summary;
      this.state.completedTasks.push(task);
      this.dirty = true;
      return task;
    }
    return null;
  }

  // Add finding
  addFinding(finding) {
    finding.id = finding.id || `finding-${Date.now()}`;
    finding.createdAt = new Date().toISOString();
    finding.status = finding.status || 'open';
    this.state.findings.push(finding);
    this.dirty = true;
    return finding;
  }

  // Add blocker
  addBlocker(blocker) {
    blocker.id = blocker.id || `blocker-${Date.now()}`;
    blocker.createdAt = new Date().toISOString();
    blocker.status = blocker.status || 'open';
    this.state.blockers.push(blocker);
    this.dirty = true;
    return blocker;
  }

  // Add message (communication history)
  addMessage(from, to, content, type = 'info') {
    const message = {
      id: `msg-${Date.now()}`,
      from,
      to, // null = broadcast
      content,
      type,
      read: false,
      timestamp: new Date().toISOString()
    };

    this.state.messages.push(message);

    // Keep only last 200 messages
    if (this.state.messages.length > 200) {
      this.state.messages = this.state.messages.slice(-200);
    }

    this.dirty = true;
    return message;
  }

  // Mark messages as read
  markMessagesRead(workerId) {
    let count = 0;
    for (const msg of this.state.messages) {
      if ((msg.to === workerId || msg.to === null || msg.to === 'all') && !msg.read) {
        msg.read = true;
        count++;
      }
    }
    if (count > 0) {
      this.dirty = true;
    }
    return count;
  }

  // Get messages for a worker (since timestamp)
  getMessages(workerId, since) {
    return this.state.messages.filter(m => {
      const isRecent = !since || new Date(m.timestamp) > new Date(since);
      const isForWorker = m.to === null || m.to === 'all' || m.to === workerId;
      return isRecent && isForWorker;
    });
  }

  // Get unread messages for a worker
  getUnreadMessages(workerId) {
    return this.state.messages.filter(m => {
      const isForWorker = m.to === null || m.to === 'all' || m.to === workerId;
      return isForWorker && !m.read;
    });
  }

  // Cleanup
  destroy() {
    clearInterval(this.saveInterval);
    if (this.dirty) {
      this.persist();
    }
  }
}

module.exports = StateManager;
