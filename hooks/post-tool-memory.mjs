#!/usr/bin/env node
/**
 * Cordelia PostToolUse Hook - Capture Claude auto-memory writes
 *
 * Fires on PostToolUse for Write/Edit tool calls matching memory paths.
 * Diffs the change, runs novelty-lite analysis, and persists high-signal
 * content to Cordelia L2 as learnings.
 *
 * Timeout: 10s (target: <3s actual)
 * Fallback: Any failure exits 0 - never block tool execution
 */
import { getEncryptionKey, getMemoryRoot } from './lib.mjs';
import { ensureServer } from './server-manager.mjs';
import { createMcpClient, writeL2 } from './mcp-client.mjs';
import { analyzeText } from './novelty-lite.mjs';

const CONFIDENCE_THRESHOLD = 0.7;

/**
 * Read PostToolUse JSON from stdin.
 */
async function readStdin() {
  return new Promise((resolve) => {
    let data = '';
    process.stdin.setEncoding('utf-8');
    process.stdin.on('data', (chunk) => { data += chunk; });
    process.stdin.on('end', () => resolve(data.trim()));
    setTimeout(() => resolve(data.trim()), 1000);
  });
}

/**
 * Extract the changed text content from the hook input.
 * Write: tool_input.content
 * Edit: tool_input.new_string
 */
function extractContent(input) {
  const toolInput = input.tool_input;
  if (!toolInput) return null;

  const filePath = toolInput.file_path;
  if (!filePath || !filePath.includes('/memory/')) return null;

  // Write tool: full file content
  if (input.tool_name === 'Write' && toolInput.content) {
    return toolInput.content;
  }

  // Edit tool: the new string being inserted
  if (input.tool_name === 'Edit' && toolInput.new_string) {
    return toolInput.new_string;
  }

  return null;
}

async function main() {
  let client;
  try {
    const stdinData = await readStdin();
    if (!stdinData) process.exit(0);

    let input;
    try {
      input = JSON.parse(stdinData);
    } catch {
      process.exit(0);
    }

    // Extract content from the tool call
    const content = extractContent(input);
    if (!content) process.exit(0);

    // Run novelty analysis on the content
    const { extracts } = analyzeText(content);
    const signals = extracts.filter(e => e.confidence >= CONFIDENCE_THRESHOLD);
    if (signals.length === 0) process.exit(0);

    // Connect to MCP server
    const passphrase = await getEncryptionKey();
    if (!passphrase) {
      console.error('[Cordelia PostToolMemory] No encryption key, skipping');
      process.exit(0);
    }

    const memoryRoot = await getMemoryRoot();
    const { baseUrl } = await ensureServer(passphrase, memoryRoot);
    client = await createMcpClient(baseUrl);

    // Persist each high-signal extract as an L2 learning
    let persisted = 0;
    for (const extract of signals) {
      try {
        const result = await writeL2(client, 'learning', {
          type: 'insight',
          content: extract.content,
          confidence: extract.confidence,
          tags: ['auto-memory', extract.signal],
        });
        if (result?.error) {
          console.error(`[Cordelia PostToolMemory] Write rejected: ${result.error}`);
        } else {
          persisted++;
        }
      } catch (err) {
        console.error(`[Cordelia PostToolMemory] Write failed: ${err.message}`);
      }
    }

    if (persisted > 0) {
      console.error(`[Cordelia PostToolMemory] Persisted ${persisted} learning(s) to L2`);
    }

  } catch (error) {
    // Never block tool execution
    console.error(`[Cordelia PostToolMemory] Error (non-fatal): ${error.message}`);
    process.exit(0);
  } finally {
    if (client) {
      try { await client.close(); } catch { /* ignore */ }
    }
  }
}

main();
