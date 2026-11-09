#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createInterface } from 'node:readline';

const projectRoot = path.dirname(fileURLToPath(import.meta.url));
const inputPath = path.resolve(
  process.argv[2] ?? path.join(projectRoot, 'ARCHITECTURE.puml'),
);
const outputPath = path.resolve(
  process.argv[3] ?? path.join(projectRoot, 'ARCHITECTURE.svg'),
);

if (process.argv.length > 4) {
  console.error('Usage: node render_plantuml.mjs [input.puml] [output.svg]');
  process.exitCode = 2;
} else {
  try {
    const source = await readFile(inputPath, 'utf8');
    const svg = await renderWithPlantUmlMcp(source);
    await writeFile(outputPath, svg, 'utf8');
    console.log(`Rendered ${inputPath} to ${outputPath}`);
  } catch (error) {
    console.error(`PlantUML render failed: ${error.message}`);
    process.exitCode = 1;
  }
}

async function renderWithPlantUmlMcp(source) {
  const isWindows = process.platform === 'win32';
  const server = spawn(
    isWindows ? process.env.ComSpec ?? 'cmd.exe' : 'npx',
    isWindows
      ? ['/d', '/s', '/c', 'npx -y @plantuml/mcp-js']
      : ['-y', '@plantuml/mcp-js'],
    {
      stdio: ['pipe', 'pipe', 'inherit'],
    },
  );
  const lines = createInterface({ input: server.stdout });
  const pending = new Map();
  let nextId = 0;
  let serverClosed = false;

  const closed = new Promise((resolve) => {
    server.once('close', (code, signal) => {
      serverClosed = true;
      const error = new Error(
        `PlantUML MCP server exited (${signal ?? `code ${code}`}).`,
      );
      for (const { reject, timer } of pending.values()) {
        clearTimeout(timer);
        reject(error);
      }
      pending.clear();
      resolve();
    });
  });

  server.once('error', (error) => {
    for (const { reject, timer } of pending.values()) {
      clearTimeout(timer);
      reject(error);
    }
    pending.clear();
  });

  lines.on('line', (line) => {
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      return;
    }
    if (message.id === undefined || !pending.has(message.id)) return;

    const { resolve, reject, timer } = pending.get(message.id);
    clearTimeout(timer);
    pending.delete(message.id);
    if (message.error) {
      reject(new Error(message.error.message ?? 'MCP request failed.'));
    } else {
      resolve(message.result);
    }
  });

  function request(method, params, timeoutMs = 60_000) {
    if (serverClosed) {
      return Promise.reject(new Error('PlantUML MCP server is not running.'));
    }

    const id = ++nextId;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`MCP request timed out: ${method}`));
      }, timeoutMs);
      pending.set(id, { resolve, reject, timer });
      server.stdin.write(
        `${JSON.stringify({
          jsonrpc: '2.0',
          id,
          method,
          params,
        })}\n`,
      );
    });
  }

  try {
    await request(
      'initialize',
      {
        protocolVersion: '2024-11-05',
        capabilities: {},
        clientInfo: { name: 'mlrc-accs-plantuml-renderer', version: '1.0.0' },
      },
      15_000,
    );
    server.stdin.write(
      `${JSON.stringify({
        jsonrpc: '2.0',
        method: 'notifications/initialized',
      })}\n`,
    );

    const result = await request('tools/call', {
      name: 'render_diagram',
      arguments: { source },
    });
    if (!result || result.isError) {
      const details = result?.content
        ?.map((item) => item.text)
        .filter(Boolean)
        .join('\n');
      throw new Error(details || 'The PlantUML MCP server could not render the diagram.');
    }

    const structuredSvg = result.structuredContent?.svg;
    if (typeof structuredSvg === 'string') return structuredSvg;

    for (const item of result.content ?? []) {
      if (typeof item.text !== 'string') continue;
      try {
        const parsed = JSON.parse(item.text);
        if (parsed.valid === false) {
          throw new Error(
            `Invalid PlantUML at line ${parsed.errorLineNumber}: ${parsed.errorMessage}`,
          );
        }
        if (typeof parsed.svg === 'string') return parsed.svg;
      } catch (error) {
        if (error.message.startsWith('Invalid PlantUML')) throw error;
      }
    }
    throw new Error('The render tool response did not contain SVG output.');
  } finally {
    server.stdin.end();
    await Promise.race([
      closed,
      new Promise((resolve) => setTimeout(resolve, 2_000)),
    ]);
    if (!serverClosed) server.kill();
    lines.close();
  }
}
