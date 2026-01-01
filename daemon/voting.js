/**
 * Voting - Sistema de votação para decisões colegiadas
 */

class Voting {
  constructor(pubsub, stateManager) {
    this.pubsub = pubsub;
    this.stateManager = stateManager;
    this.activeVotes = new Map(); // voteId -> Vote object
  }

  /**
   * Criar uma nova votação
   * @param {string} initiator - Worker que iniciou
   * @param {string} decision - Descrição da decisão
   * @param {string[]} options - Opções de voto
   * @param {number} timeout - Timeout em ms (default 60s)
   * @param {number} quorum - Mínimo de votos necessários (default: todos workers ativos)
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

    // Publicar solicitação de voto
    this.pubsub.publish('vote.request', {
      voteId,
      decision,
      options,
      initiator,
      timeout,
      quorum: vote.quorum
    }, initiator);

    // Configurar timeout
    setTimeout(() => {
      this.closeVote(voteId);
    }, timeout);

    console.log(`[Voting] Created vote ${voteId}: "${decision}"`);
    return vote;
  }

  /**
   * Registrar voto de um worker
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

    // Publicar que voto foi registrado
    this.pubsub.publish('vote.cast', {
      voteId,
      workerId,
      option,
      currentCount: Object.keys(vote.votes).length,
      quorum: vote.quorum
    });

    console.log(`[Voting] ${workerId} voted "${option}" on ${voteId}`);

    // Verificar se atingiu quorum
    if (Object.keys(vote.votes).length >= vote.quorum) {
      this.closeVote(voteId);
    }

    return { success: true, vote };
  }

  /**
   * Fechar votação e calcular resultado
   */
  closeVote(voteId) {
    const vote = this.activeVotes.get(voteId);

    if (!vote || vote.status !== 'open') {
      return null;
    }

    vote.status = 'closed';
    vote.closedAt = new Date().toISOString();

    // Contar votos
    const counts = {};
    for (const option of vote.options) {
      counts[option] = 0;
    }

    for (const option of Object.values(vote.votes)) {
      counts[option]++;
    }

    // Determinar vencedor
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

    // Publicar resultado
    this.pubsub.publish('vote.result', {
      voteId,
      decision: vote.decision,
      result: vote.result,
      votes: vote.votes
    });

    console.log(`[Voting] Vote ${voteId} closed. Winner: ${vote.result.winner || 'TIE'}`);

    // Manter no histórico por 1 hora, depois limpar
    setTimeout(() => {
      this.activeVotes.delete(voteId);
    }, 3600000);

    return vote.result;
  }

  /**
   * Obter status de uma votação
   */
  getVoteStatus(voteId) {
    return this.activeVotes.get(voteId) || null;
  }

  /**
   * Listar votações ativas
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
