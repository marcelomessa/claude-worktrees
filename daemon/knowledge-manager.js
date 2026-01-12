/**
 * Knowledge Manager - MCP Knowledge Base for CWT
 *
 * Manages patterns, guidelines, architecture decisions, and safety rules.
 * Supports hybrid architecture: global (~/.cwt/knowledge) + project (.cwt/knowledge)
 *
 * Priority: project > global (project overrides global)
 */

const fs = require('fs');
const path = require('path');

class KnowledgeManager {
  constructor(projectRoot, globalRoot = null) {
    this.projectRoot = projectRoot;
    this.projectKbDir = path.join(projectRoot, '.cwt', 'knowledge');
    this.globalKbDir = globalRoot || path.join(process.env.HOME, '.cwt', 'knowledge');

    this.categories = ['patterns', 'guidelines', 'architecture', 'safety', 'discoveries'];

    // Cache for loaded entries
    this.cache = new Map();
    this.cacheExpiry = 60000; // 1 minute

    // Ensure directories exist
    this.ensureDirectories();

    console.log(`[KnowledgeManager] Initialized`);
    console.log(`  Project KB: ${this.projectKbDir}`);
    console.log(`  Global KB: ${this.globalKbDir}`);
  }

  ensureDirectories() {
    // Create project knowledge directories
    for (const category of this.categories) {
      const dir = path.join(this.projectKbDir, category);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
    }

    // Create index if not exists
    const indexPath = path.join(this.projectKbDir, 'index.json');
    if (!fs.existsSync(indexPath)) {
      this.saveIndex({
        version: '1.0.0',
        projectName: path.basename(this.projectRoot),
        lastUpdated: new Date().toISOString(),
        categories: {},
        aliases: {},
        stats: { totalEntries: 0, totalQueries: 0 }
      });
    }
  }

  // ==========================================================================
  // INDEX MANAGEMENT
  // ==========================================================================

  loadIndex(kbDir = this.projectKbDir) {
    const indexPath = path.join(kbDir, 'index.json');
    try {
      if (fs.existsSync(indexPath)) {
        return JSON.parse(fs.readFileSync(indexPath, 'utf8'));
      }
    } catch (e) {
      console.error(`[KnowledgeManager] Error loading index from ${kbDir}:`, e.message);
    }
    return { categories: {}, aliases: {}, stats: {} };
  }

  saveIndex(index, kbDir = this.projectKbDir) {
    const indexPath = path.join(kbDir, 'index.json');
    try {
      index.lastUpdated = new Date().toISOString();
      fs.writeFileSync(indexPath, JSON.stringify(index, null, 2));
      return true;
    } catch (e) {
      console.error(`[KnowledgeManager] Error saving index:`, e.message);
      return false;
    }
  }

  // ==========================================================================
  // ENTRY LOADING (with priority resolution)
  // ==========================================================================

  loadEntry(id) {
    // Check cache
    const cached = this.cache.get(id);
    if (cached && Date.now() - cached.loadedAt < this.cacheExpiry) {
      return cached.entry;
    }

    // Try project first (higher priority)
    let entry = this.loadEntryFromDir(id, this.projectKbDir);
    if (entry) {
      entry._source = 'project';
      this.cache.set(id, { entry, loadedAt: Date.now() });
      return entry;
    }

    // Fall back to global
    entry = this.loadEntryFromDir(id, this.globalKbDir);
    if (entry) {
      entry._source = 'global';
      this.cache.set(id, { entry, loadedAt: Date.now() });
      return entry;
    }

    return null;
  }

  loadEntryFromDir(id, kbDir) {
    // Parse ID: "pattern-error-handling" -> category: patterns, name: error-handling
    const match = id.match(/^(\w+)-(.+)$/);
    if (!match) return null;

    const [, categoryPrefix, name] = match;
    const category = this.categoryFromPrefix(categoryPrefix);
    if (!category) return null;

    // Try .json first, then .md
    const jsonPath = path.join(kbDir, category, `${name}.json`);
    const mdPath = path.join(kbDir, category, `${name}.md`);

    try {
      if (fs.existsSync(jsonPath)) {
        const data = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
        return { id, ...data };
      }

      if (fs.existsSync(mdPath)) {
        const content = fs.readFileSync(mdPath, 'utf8');
        return this.parseMarkdownEntry(id, category, name, content);
      }
    } catch (e) {
      console.error(`[KnowledgeManager] Error loading entry ${id}:`, e.message);
    }

    return null;
  }

  parseMarkdownEntry(id, category, name, content) {
    // Extract frontmatter if present (---\n...\n---)
    let metadata = {};
    let body = content;

    const frontmatterMatch = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
    if (frontmatterMatch) {
      try {
        // Simple YAML-like parsing for keywords, title, etc.
        const fm = frontmatterMatch[1];
        fm.split('\n').forEach(line => {
          const [key, ...valueParts] = line.split(':');
          if (key && valueParts.length) {
            const value = valueParts.join(':').trim();
            if (value.startsWith('[')) {
              // Array: [a, b, c]
              metadata[key.trim()] = value.slice(1, -1).split(',').map(s => s.trim());
            } else {
              metadata[key.trim()] = value;
            }
          }
        });
        body = frontmatterMatch[2];
      } catch (e) {
        // Ignore frontmatter parsing errors
      }
    }

    // Extract title from first heading
    const titleMatch = body.match(/^#\s+(.+)$/m);
    const title = metadata.title || (titleMatch ? titleMatch[1] : name);

    return {
      id,
      type: this.prefixFromCategory(category),
      category: name,
      title,
      keywords: metadata.keywords || this.extractKeywords(body),
      content: body,
      createdAt: metadata.createdAt || new Date().toISOString(),
      createdBy: metadata.createdBy || 'unknown'
    };
  }

  extractKeywords(content) {
    // Simple keyword extraction from content
    const words = content.toLowerCase()
      .replace(/[^a-z0-9\s]/g, ' ')
      .split(/\s+/)
      .filter(w => w.length > 3);

    // Count frequency
    const freq = {};
    words.forEach(w => freq[w] = (freq[w] || 0) + 1);

    // Return top 10 most frequent
    return Object.entries(freq)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 10)
      .map(([word]) => word);
  }

  categoryFromPrefix(prefix) {
    const map = {
      'pattern': 'patterns',
      'guide': 'guidelines',
      'arch': 'architecture',
      'safety': 'safety',
      'discovery': 'discoveries'
    };
    return map[prefix];
  }

  prefixFromCategory(category) {
    const map = {
      'patterns': 'pattern',
      'guidelines': 'guide',
      'architecture': 'arch',
      'safety': 'safety',
      'discoveries': 'discovery'
    };
    return map[category];
  }

  // ==========================================================================
  // QUERY (search by text/keywords)
  // ==========================================================================

  query(params) {
    const { query, category, limit = 5, include_examples = false } = params;

    if (!query) {
      return { found: false, entries: [], suggestions: ['Try: "error handling", "testing", "api design"'] };
    }

    const queryLower = query.toLowerCase();
    const queryWords = queryLower.split(/\s+/).filter(w => w.length > 2);

    // Get all entries
    const allEntries = this.listAllEntries(category);

    // Score each entry
    const scored = allEntries.map(entry => {
      let score = 0;

      // Exact match in title
      if (entry.title.toLowerCase().includes(queryLower)) {
        score += 100;
      }

      // Keyword matches
      const keywords = entry.keywords || [];
      for (const kw of keywords) {
        if (queryWords.some(qw => kw.includes(qw) || qw.includes(kw))) {
          score += 20;
        }
      }

      // Word matches in content
      const contentLower = (entry.content || '').toLowerCase();
      for (const qw of queryWords) {
        if (contentLower.includes(qw)) {
          score += 5;
        }
      }

      // Alias match
      const index = this.loadIndex();
      for (const [alias, targetId] of Object.entries(index.aliases || {})) {
        if (alias.toLowerCase().includes(queryLower) && targetId === entry.id) {
          score += 50;
        }
      }

      return { ...entry, _score: score };
    });

    // Filter and sort by score
    const results = scored
      .filter(e => e._score > 0)
      .sort((a, b) => b._score - a._score)
      .slice(0, limit);

    // Update stats
    this.updateQueryStats(query);

    // Format results
    const entries = results.map(e => ({
      id: e.id,
      title: e.title,
      relevance: Math.min(e._score / 100, 1),
      summary: (e.content || '').slice(0, 200) + '...',
      content: e._score >= 50 ? e.content : undefined,
      examples: include_examples ? e.examples : undefined,
      _source: e._source
    }));

    return {
      found: entries.length > 0,
      entries,
      suggestions: entries.length === 0 ? this.getSuggestions(queryWords) : undefined
    };
  }

  listAllEntries(category = null) {
    const entries = [];
    const categories = category ? [category] : this.categories;

    for (const cat of categories) {
      // From project
      entries.push(...this.listEntriesFromDir(cat, this.projectKbDir, 'project'));

      // From global (if not already in project)
      const globalEntries = this.listEntriesFromDir(cat, this.globalKbDir, 'global');
      for (const ge of globalEntries) {
        if (!entries.some(e => e.id === ge.id)) {
          entries.push(ge);
        }
      }
    }

    return entries;
  }

  listEntriesFromDir(category, kbDir, source) {
    const entries = [];
    const dir = path.join(kbDir, category);

    if (!fs.existsSync(dir)) return entries;

    try {
      const files = fs.readdirSync(dir);
      for (const file of files) {
        if (file.endsWith('.md') || file.endsWith('.json')) {
          const name = file.replace(/\.(md|json)$/, '');
          const prefix = this.prefixFromCategory(category);
          const id = `${prefix}-${name}`;
          const entry = this.loadEntry(id);
          if (entry) {
            entries.push(entry);
          }
        }
      }
    } catch (e) {
      // Ignore errors
    }

    return entries;
  }

  getSuggestions(queryWords) {
    // Return some common entry names as suggestions
    const allEntries = this.listAllEntries();
    return allEntries
      .slice(0, 5)
      .map(e => e.title);
  }

  updateQueryStats(query) {
    try {
      const index = this.loadIndex();
      index.stats = index.stats || {};
      index.stats.totalQueries = (index.stats.totalQueries || 0) + 1;
      index.stats.lastQuery = query;
      index.stats.lastQueryAt = new Date().toISOString();
      this.saveIndex(index);
    } catch (e) {
      // Ignore stats errors
    }
  }

  // ==========================================================================
  // LIST
  // ==========================================================================

  list(params = {}) {
    const { category } = params;
    const result = { categories: [] };

    const categories = category ? [category] : this.categories;

    for (const cat of categories) {
      const entries = this.listAllEntries(cat);
      if (entries.length > 0 || !category) {
        result.categories.push({
          name: cat,
          description: this.getCategoryDescription(cat),
          count: entries.length,
          entries: entries.map(e => ({ id: e.id, title: e.title, _source: e._source }))
        });
      }
    }

    return result;
  }

  getCategoryDescription(category) {
    const descriptions = {
      'patterns': 'Code patterns and templates',
      'guidelines': 'Coding guidelines and conventions',
      'architecture': 'Architecture decisions',
      'safety': 'Safety rules and restrictions',
      'discoveries': 'Worker discoveries and findings'
    };
    return descriptions[category] || category;
  }

  // ==========================================================================
  // GET
  // ==========================================================================

  get(id) {
    const entry = this.loadEntry(id);
    return { found: !!entry, entry };
  }

  // ==========================================================================
  // ADD (coordinator only - enforced at socket-server level)
  // ==========================================================================

  add(params) {
    const { type, category, title, content, keywords = [], examples = [], aliases = [] } = params;

    if (!type || !title || !content) {
      return { success: false, message: 'Missing required fields: type, title, content' };
    }

    const catDir = type === 'pattern' ? 'patterns'
                 : type === 'guide' ? 'guidelines'
                 : type === 'arch' ? 'architecture'
                 : type === 'safety' ? 'safety'
                 : type === 'discovery' ? 'discoveries'
                 : null;

    if (!catDir) {
      return { success: false, message: `Invalid type: ${type}. Use: pattern, guide, arch, safety, discovery` };
    }

    // Generate ID from title
    const name = title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
    const id = `${type}-${name}`;

    // Create entry object
    const entry = {
      id,
      type,
      category: category || name,
      title,
      keywords: keywords.length ? keywords : this.extractKeywords(content),
      content,
      examples,
      createdBy: 'coordinator',
      createdAt: new Date().toISOString()
    };

    // Save as JSON
    const filePath = path.join(this.projectKbDir, catDir, `${name}.json`);
    try {
      fs.writeFileSync(filePath, JSON.stringify(entry, null, 2));
    } catch (e) {
      return { success: false, message: `Error saving entry: ${e.message}` };
    }

    // Update index with aliases
    const index = this.loadIndex();
    index.categories[catDir] = index.categories[catDir] || { entries: [] };
    if (!index.categories[catDir].entries.includes(id)) {
      index.categories[catDir].entries.push(id);
    }
    for (const alias of aliases) {
      index.aliases[alias.toLowerCase()] = id;
    }
    index.stats.totalEntries = (index.stats.totalEntries || 0) + 1;
    this.saveIndex(index);

    // Clear cache
    this.cache.delete(id);

    console.log(`[KnowledgeManager] Added entry: ${id}`);
    return { success: true, id, message: `Entry '${title}' added successfully` };
  }

  // ==========================================================================
  // UPDATE
  // ==========================================================================

  update(id, updates) {
    const existing = this.loadEntry(id);
    if (!existing) {
      return { success: false, message: `Entry not found: ${id}` };
    }

    // Can only update project entries
    if (existing._source !== 'project') {
      return { success: false, message: `Cannot update global entry. Create a project override instead.` };
    }

    const updated = { ...existing, ...updates, updatedAt: new Date().toISOString() };
    delete updated._source;
    delete updated._score;

    // Determine file path
    const category = this.categoryFromPrefix(existing.type);
    const name = id.replace(`${existing.type}-`, '');
    const filePath = path.join(this.projectKbDir, category, `${name}.json`);

    try {
      fs.writeFileSync(filePath, JSON.stringify(updated, null, 2));
      this.cache.delete(id);
      console.log(`[KnowledgeManager] Updated entry: ${id}`);
      return { success: true, id, message: `Entry updated successfully` };
    } catch (e) {
      return { success: false, message: `Error updating entry: ${e.message}` };
    }
  }

  // ==========================================================================
  // DELETE
  // ==========================================================================

  delete(id) {
    const existing = this.loadEntry(id);
    if (!existing) {
      return { success: false, message: `Entry not found: ${id}` };
    }

    if (existing._source !== 'project') {
      return { success: false, message: `Cannot delete global entry.` };
    }

    const category = this.categoryFromPrefix(existing.type);
    const name = id.replace(`${existing.type}-`, '');

    // Try both .json and .md
    const jsonPath = path.join(this.projectKbDir, category, `${name}.json`);
    const mdPath = path.join(this.projectKbDir, category, `${name}.md`);

    try {
      if (fs.existsSync(jsonPath)) fs.unlinkSync(jsonPath);
      if (fs.existsSync(mdPath)) fs.unlinkSync(mdPath);

      // Update index
      const index = this.loadIndex();
      if (index.categories[category]) {
        index.categories[category].entries = index.categories[category].entries.filter(e => e !== id);
      }
      // Remove aliases pointing to this entry
      for (const [alias, targetId] of Object.entries(index.aliases)) {
        if (targetId === id) delete index.aliases[alias];
      }
      this.saveIndex(index);

      this.cache.delete(id);
      console.log(`[KnowledgeManager] Deleted entry: ${id}`);
      return { success: true, message: `Entry deleted successfully` };
    } catch (e) {
      return { success: false, message: `Error deleting entry: ${e.message}` };
    }
  }

  // ==========================================================================
  // LEARN (save Q&A as pattern)
  // ==========================================================================

  learn(params) {
    const { question, answer, title, category = 'patterns', keywords = [] } = params;

    if (!question || !answer) {
      return { success: false, message: 'Missing required fields: question, answer' };
    }

    const entryTitle = title || question.slice(0, 50);
    const content = `# ${entryTitle}\n\n## Question\n${question}\n\n## Answer\n${answer}`;

    return this.add({
      type: 'pattern',
      category,
      title: entryTitle,
      content,
      keywords: [...keywords, ...this.extractKeywords(question + ' ' + answer)]
    });
  }

  // ==========================================================================
  // SAFETY RULES
  // ==========================================================================

  getSafetyRules() {
    const rulesPath = path.join(this.projectKbDir, 'safety', 'rules.json');
    try {
      if (fs.existsSync(rulesPath)) {
        return JSON.parse(fs.readFileSync(rulesPath, 'utf8'));
      }
    } catch (e) {
      console.error('[KnowledgeManager] Error loading safety rules:', e.message);
    }
    return { rules: [] };
  }

  addSafetyRule(rule) {
    const rules = this.getSafetyRules();
    rule.id = rule.id || `rule-${Date.now()}`;
    rule.createdAt = new Date().toISOString();
    rules.rules.push(rule);

    const rulesPath = path.join(this.projectKbDir, 'safety', 'rules.json');
    try {
      fs.writeFileSync(rulesPath, JSON.stringify(rules, null, 2));
      console.log(`[KnowledgeManager] Added safety rule: ${rule.id}`);
      return { success: true, id: rule.id, message: 'Safety rule added' };
    } catch (e) {
      return { success: false, message: `Error adding safety rule: ${e.message}` };
    }
  }

  checkSafety(action, actionType = 'command') {
    const rules = this.getSafetyRules();

    for (const rule of rules.rules) {
      if (rule.check_type !== `${actionType}_pattern`) continue;

      try {
        const regex = new RegExp(rule.pattern);
        if (regex.test(action)) {
          return {
            allowed: rule.action !== 'block',
            rule_id: rule.id,
            message: rule.message,
            action: rule.action
          };
        }
      } catch (e) {
        // Invalid regex, skip
      }
    }

    return { allowed: true };
  }

  // ==========================================================================
  // DISCOVERIES
  // ==========================================================================

  addDiscovery(params) {
    const { title, content, workerId, relevance = [], confidence = 'suspected' } = params;

    return this.add({
      type: 'discovery',
      title,
      content,
      keywords: relevance,
      examples: [{ workerId, confidence, createdAt: new Date().toISOString() }]
    });
  }

  listDiscoveries(params = {}) {
    const { since } = params;
    const discoveries = this.listAllEntries('discoveries');

    if (since) {
      const sinceDate = new Date(since);
      return discoveries.filter(d => new Date(d.createdAt) > sinceDate);
    }

    return discoveries;
  }

  // ==========================================================================
  // CLEANUP
  // ==========================================================================

  destroy() {
    this.cache.clear();
    console.log('[KnowledgeManager] Destroyed');
  }
}

module.exports = KnowledgeManager;
