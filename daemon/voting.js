/**
 * Voting - Voting system for collegial decisions
 */

class Voting {
  constructor(pubsub, stateManager) {
    this.pubsub = pubsub;
    this.stateManager = stateManager;
    this.activeVotes = new Map(); // voteId -> Vote object
  }

  /**
   * Create a new vote
   * @param {string} initiator - Worker that initiated
   * @param {string} decision - Decision description
   * @param {string[]} options - Voting options
   * @param {number} timeout - Timeout in ms (default 60s)
   * @param {number} quorum - Minimum votes required (default: all active workers)
   */
  createVote(initiator, decision, options, timeout = 60000, quorum = null) {
    const voteId = `vote-${Date.now()}`;
    const activeWorkers = this.stateManager.getActiveWorkers();

    const vote = {
      id: voteId,
      initiator,
      decision,
      options,
      votes: {}, // workerId -> option
      quorum: quorum || activeWorkers.length,
      timeout,
      createdAt: new Date().toISOString(),
      status: 'open',
      result: null
    };

    this.activeVotes.set(voteId, vote);

    // Publish vote request
    this.pubsub.publish('vote.request', {
      voteId,
      decision,
      options,
      initiator,
      timeout,
      quorum: vote.quorum
    }, initiator);

    // Set timeout
    setTimeout(() => {
      this.closeVote(voteId);
    }, timeout);

    console.log(`[Voting] Created vote ${voteId}: "${decision}"`);
    return vote;
  }

  /**
   * Register a worker's vote
   */
  castVote(voteId, workerId, option) {
    const vote = this.activeVotes.get(voteId);

    if (!vote) {
      return { success: false, error: 'Vote not found' };
    }

    if (vote.status !== 'open') {
      return { success: false, error: 'Vote already closed' };
    }

    if (!vote.options.includes(option)) {
      return { success: false, error: 'Invalid option' };
    }

    vote.votes[workerId] = option;

    // Publish that vote was recorded
    this.pubsub.publish('vote.cast', {
      voteId,
      workerId,
      option,
      currentCount: Object.keys(vote.votes).length,
      quorum: vote.quorum
    });

    console.log(`[Voting] ${workerId} voted "${option}" on ${voteId}`);

    // Check if quorum reached
    if (Object.keys(vote.votes).length >= vote.quorum) {
      this.closeVote(voteId);
    }

    return { success: true, vote };
  }

  /**
   * Close vote and calculate result
   */
  closeVote(voteId) {
    const vote = this.activeVotes.get(voteId);

    if (!vote || vote.status !== 'open') {
      return null;
    }

    vote.status = 'closed';
    vote.closedAt = new Date().toISOString();

    // Count votes
    const counts = {};
    for (const option of vote.options) {
      counts[option] = 0;
    }

    for (const option of Object.values(vote.votes)) {
      counts[option]++;
    }

    // Determine winner
    let winner = null;
    let maxVotes = 0;
    let tie = false;

    for (const [option, count] of Object.entries(counts)) {
      if (count > maxVotes) {
        winner = option;
        maxVotes = count;
        tie = false;
      } else if (count === maxVotes && count > 0) {
        tie = true;
      }
    }

    vote.result = {
      winner: tie ? null : winner,
      tie,
      counts,
      totalVotes: Object.keys(vote.votes).length,
      quorumReached: Object.keys(vote.votes).length >= vote.quorum
    };

    // Publish result
    this.pubsub.publish('vote.result', {
      voteId,
      decision: vote.decision,
      result: vote.result,
      votes: vote.votes
    });

    console.log(`[Voting] Vote ${voteId} closed. Winner: ${vote.result.winner || 'TIE'}`);

    // Keep in history for 1 hour, then clean up
    setTimeout(() => {
      this.activeVotes.delete(voteId);
    }, 3600000);

    return vote.result;
  }

  /**
   * Get vote status
   */
  getVoteStatus(voteId) {
    return this.activeVotes.get(voteId) || null;
  }

  /**
   * List active votes
   */
  getActiveVotes() {
    const active = [];
    for (const vote of this.activeVotes.values()) {
      if (vote.status === 'open') {
        active.push({
          id: vote.id,
          decision: vote.decision,
          options: vote.options,
          currentVotes: Object.keys(vote.votes).length,
          quorum: vote.quorum
        });
      }
    }
    return active;
  }
}

module.exports = Voting;
