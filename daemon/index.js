#!/usr/bin/env node

/**
 * CWT Daemon - Communication coordinator between Claude agents
 *
 * Manages real-time communication via Unix socket per project.
 *
 * Usage:
 *   node daemon/index.js <project-root>
 *   node daemon/index.js /path/to/project   # Socket at /path/to/project/.cwt/cwt.sock
 *
 * The daemon uses:
 *   - Socket: <project-root>/.cwt/cwt.sock
 *   - State:  <project-root>/.cwt/state.json
 */

const path = require('path');
const fs = require('fs');
const StateManager = require('./state-manager');
const PubSub = require('./pubsub');
const Voting = require('./voting');
const SocketServer = require('./socket-server');
const KnowledgeManager = require('./knowledge-manager');

// Determine project root
const PROJECT_ROOT = process.argv[2] || process.cwd();
// In legacy mode (git worktrees without .cwt/) the launcher keeps state outside
// the repo and points us at it via CWT_STATE_DIR.
const CWT_DIR = process.env.CWT_STATE_DIR || path.join(PROJECT_ROOT, '.cwt');

// Validate that the state directory exists
if (!fs.existsSync(CWT_DIR)) {
  console.error(`Error: state directory not found: ${CWT_DIR}`);
  console.error('Run "cwt init" first to initialize the project.');
  process.exit(1);
}

const SOCKET_PATH = path.join(CWT_DIR, 'cwt.sock');
const STATE_FILE = path.join(CWT_DIR, 'state.json');

// Read project name from config
let projectName = path.basename(PROJECT_ROOT);
try {
  const config = JSON.parse(fs.readFileSync(path.join(CWT_DIR, 'config.json'), 'utf8'));
  projectName = config.name || projectName;
} catch (e) {
  // Use directory name
}

console.log('═══════════════════════════════════════════════════════');
console.log('  CWT DAEMON - Multi-Agent Coordination');
console.log('═══════════════════════════════════════════════════════');
console.log(`  Project: ${projectName}`);
console.log(`  Root:    ${PROJECT_ROOT}`);
console.log(`  Socket:  ${SOCKET_PATH}`);
console.log(`  State:   ${STATE_FILE}`);
console.log(`  PID:     ${process.pid}`);
console.log('═══════════════════════════════════════════════════════');
console.log('');

// Save PID so tmux-launcher can kill the daemon later
fs.writeFileSync(path.join(CWT_DIR, 'daemon.pid'), String(process.pid));

// Initialize components
const stateManager = new StateManager(STATE_FILE, projectName);
const pubsub = new PubSub();
const voting = new Voting(pubsub, stateManager);
const knowledgeManager = new KnowledgeManager(PROJECT_ROOT);
const socketServer = new SocketServer(SOCKET_PATH, stateManager, pubsub, voting, knowledgeManager);

// Start server
socketServer.start();

// Periodic status
const statusInterval = setInterval(() => {
  const workers = stateManager.getActiveWorkers();
  const stats = pubsub.getStats();
  const votes = voting.getActiveVotes();

  console.log(`[Status] Workers: ${workers.length} | Clients: ${stats.clients} | Votes: ${votes.length}`);
}, 60000);

// Graceful shutdown
const shutdown = (signal) => {
  console.log(`\n[Daemon] Received ${signal}, shutting down...`);

  clearInterval(statusInterval);
  socketServer.stop();
  stateManager.destroy();

  // Remove PID file
  try {
    fs.unlinkSync(path.join(CWT_DIR, 'daemon.pid'));
  } catch (e) {}

  console.log('[Daemon] Goodbye!');
  process.exit(0);
};

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

// Catch unhandled errors
process.on('uncaughtException', (err) => {
  console.error('[Daemon] Uncaught exception:', err);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('[Daemon] Unhandled rejection:', reason);
});

console.log('[Daemon] Ready! Waiting for connections...');
console.log('[Daemon] Press Ctrl+C to stop');
console.log('');
