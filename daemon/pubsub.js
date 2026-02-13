/**
 * PubSub - Publish/subscribe system
 */

class PubSub {
  constructor() {
    this.subscriptions = new Map(); // topic -> Set of callbacks
    this.clientSubscriptions = new Map(); // clientId -> Set of topics
  }

  // Available topics
  static TOPICS = {
    // Tasks
    TASK_CREATED: 'task.created',
    TASK_ASSIGNED: 'task.assigned',
    TASK_STARTED: 'task.started',
    TASK_PROGRESS: 'task.progress',
    TASK_COMPLETED: 'task.completed',
    TASK_FAILED: 'task.failed',

    // Findings
    FINDING_REPORTED: 'finding.reported',
    FINDING_RESOLVED: 'finding.resolved',

    // Workers
    WORKER_REGISTERED: 'worker.registered',
    WORKER_HEARTBEAT: 'worker.heartbeat',
    WORKER_DISCONNECTED: 'worker.disconnected',

    // Voting
    VOTE_REQUEST: 'vote.request',
    VOTE_CAST: 'vote.cast',
    VOTE_RESULT: 'vote.result',

    // Context
    CONTEXT_SYNC: 'context.sync',
    BLOCKER_ADDED: 'blocker.added',
    BLOCKER_RESOLVED: 'blocker.resolved',

    // Coordination
    BROADCAST: 'broadcast',
    DIRECT_MESSAGE: 'direct.message'
  };

  // Subscribe to a topic
  subscribe(clientId, topic, callback) {
    // Add callback to topic
    if (!this.subscriptions.has(topic)) {
      this.subscriptions.set(topic, new Set());
    }
    this.subscriptions.get(topic).add({ clientId, callback });

    // Track client subscriptions
    if (!this.clientSubscriptions.has(clientId)) {
      this.clientSubscriptions.set(clientId, new Set());
    }
    this.clientSubscriptions.get(clientId).add(topic);

    console.log(`[PubSub] ${clientId} subscribed to ${topic}`);
    return true;
  }

  // Unsubscribe from a topic
  unsubscribe(clientId, topic) {
    if (this.subscriptions.has(topic)) {
      const subs = this.subscriptions.get(topic);
      for (const sub of subs) {
        if (sub.clientId === clientId) {
          subs.delete(sub);
          break;
        }
      }
    }

    if (this.clientSubscriptions.has(clientId)) {
      this.clientSubscriptions.get(clientId).delete(topic);
    }

    return true;
  }

  // Unsubscribe from all topics (when client disconnects)
  unsubscribeAll(clientId) {
    const topics = this.clientSubscriptions.get(clientId);
    if (topics) {
      for (const topic of topics) {
        this.unsubscribe(clientId, topic);
      }
      this.clientSubscriptions.delete(clientId);
    }
    console.log(`[PubSub] ${clientId} unsubscribed from all topics`);
  }

  // Publish message to a topic
  publish(topic, data, fromClientId = null) {
    const message = {
      topic,
      data,
      from: fromClientId,
      timestamp: new Date().toISOString()
    };

    const subs = this.subscriptions.get(topic);
    if (!subs || subs.size === 0) {
      console.log(`[PubSub] No subscribers for ${topic}`);
      return 0;
    }

    let delivered = 0;
    for (const sub of subs) {
      // Don't send to the sender itself
      if (sub.clientId !== fromClientId) {
        try {
          sub.callback(message);
          delivered++;
        } catch (e) {
          console.error(`[PubSub] Error delivering to ${sub.clientId}:`, e.message);
        }
      }
    }

    console.log(`[PubSub] Published to ${topic}: ${delivered} delivered`);
    return delivered;
  }

  // Publish to all clients (broadcast)
  broadcast(data, fromClientId = null) {
    return this.publish(PubSub.TOPICS.BROADCAST, data, fromClientId);
  }

  // Send direct message to a specific client
  sendDirect(toClientId, data, fromClientId) {
    const message = {
      topic: PubSub.TOPICS.DIRECT_MESSAGE,
      data,
      from: fromClientId,
      to: toClientId,
      timestamp: new Date().toISOString()
    };

    const topics = this.clientSubscriptions.get(toClientId);
    if (!topics || !topics.has(PubSub.TOPICS.DIRECT_MESSAGE)) {
      console.log(`[PubSub] ${toClientId} not subscribed to direct messages`);
      return false;
    }

    const subs = this.subscriptions.get(PubSub.TOPICS.DIRECT_MESSAGE);
    for (const sub of subs) {
      if (sub.clientId === toClientId) {
        try {
          sub.callback(message);
          return true;
        } catch (e) {
          console.error(`[PubSub] Error sending direct to ${toClientId}:`, e.message);
          return false;
        }
      }
    }

    return false;
  }

  // Get statistics
  getStats() {
    const stats = {
      topics: {},
      clients: this.clientSubscriptions.size
    };

    for (const [topic, subs] of this.subscriptions) {
      stats.topics[topic] = subs.size;
    }

    return stats;
  }
}

module.exports = PubSub;
