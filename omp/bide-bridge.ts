import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import * as fs from "node:fs";
import * as path from "node:path";

const MUTATING: Record<string, true> = {
  write: true,
  edit: true,
  ast_edit: true,
  notebook: true,
};
const turnFiles = new Map<string, number | undefined>(); // module-global: shared with subagents

interface FileEntry {
  path: string;
  line?: number;
}

function collectFiles(
  event: { input?: Record<string, unknown>; details?: unknown },
  cwd: string,
): FileEntry[] {
  const rawList: { rawPath: string; line?: number }[] = [];

  const inputPath =
    typeof event.input?.path === "string"
      ? event.input.path
      : typeof event.input?.file_path === "string"
        ? event.input.file_path
        : undefined;

  if (inputPath) {
    rawList.push({ rawPath: inputPath });
  }

  const seen = new Set<unknown>();
  function walk(obj: unknown, depth: number) {
    if (depth > 4 || !obj || typeof obj !== "object" || seen.has(obj)) return;
    seen.add(obj);

    if (Array.isArray(obj)) {
      for (const item of obj) {
        walk(item, depth + 1);
      }
      return;
    }

    const record = obj as Record<string, unknown>;
    const p =
      typeof record.path === "string"
        ? record.path
        : typeof record.file_path === "string"
          ? record.file_path
          : undefined;

    if (p) {
      const line =
        typeof record.firstChangedLine === "number"
          ? record.firstChangedLine
          : typeof record.line === "number"
            ? record.line
            : undefined;
      rawList.push({ rawPath: p, line });
    }

    for (const val of Object.values(record)) {
      if (val && typeof val === "object") {
        walk(val, depth + 1);
      }
    }
  }

  if (event.details) {
    walk(event.details, 0);
  }

  const byPath = new Map<string, number | undefined>();
  for (const item of rawList) {
    const resolved = path.resolve(cwd, item.rawPath);
    try {
      const stat = fs.statSync(resolved, { throwIfNoEntry: false });
      if (!stat || !stat.isFile()) continue;
    } catch {
      continue;
    }

    if (!byPath.has(resolved)) {
      byPath.set(resolved, item.line);
    } else if (byPath.get(resolved) === undefined && item.line !== undefined) {
      byPath.set(resolved, item.line);
    }
  }

  const topDetails = event.details as Record<string, unknown> | undefined;
  if (
    topDetails &&
    typeof topDetails === "object" &&
    typeof topDetails.firstChangedLine === "number" &&
    byPath.size === 1
  ) {
    const [solePath] = byPath.keys();
    if (byPath.get(solePath) === undefined) {
      byPath.set(solePath, topDetails.firstChangedLine as number);
    }
  }

  const result: FileEntry[] = [];
  for (const [p, l] of byPath.entries()) {
    result.push({ path: p, line: l });
  }
  return result;
}

export default function bideBridge(pi: ExtensionAPI) {
  const server = process.env.NVIM;
  const nvimBin = process.env.BIDE_NVIM_BIN;
  if (!server || !nvimBin) return; // inert outside the bide panel

  const expr = (fn: string, arg?: string) =>
    `v:lua.require'bide.omp'.${fn}(${arg === undefined ? "" : `'${arg.replaceAll("'", "''")}'`})`;

  const notify = (payload: unknown) => {
    try {
      const proc = Bun.spawn(
        [
          nvimBin,
          "--server",
          server,
          "--remote-expr",
          expr("on_change", JSON.stringify(payload)),
        ],
        {
          stdout: "ignore",
          stderr: "ignore",
          timeout: 5000,
          env: { ...process.env, NVIM_APPNAME: "bide" },
        },
      );
      proc.exited.catch(() => {});
    } catch {
      /* nvim gone: ignore */
    }
  };

  pi.on("tool_result", async (event, ctx) => {
    if (event.isError || !MUTATING[event.toolName]) return undefined;
    const files = collectFiles(event, ctx.cwd);
    if (files.length > 0) {
      notify({ kind: "edit", files });
      for (const f of files) {
        if (!turnFiles.has(f.path) || (turnFiles.get(f.path) === undefined && f.line !== undefined)) {
          turnFiles.set(f.path, f.line);
        }
      }
    }
    return undefined;
  });

  pi.on("agent_end", async (_e, ctx) => {
    if ((!ctx.agent || ctx.agent.kind === "main") && turnFiles.size > 0) {
      const files = [...turnFiles].map(([p, l]) => ({ path: p, line: l }));
      notify({ kind: "turn", files });
      turnFiles.clear();
    }
  });

  pi.registerTool({
    name: "nvim_context",
    label: "Neovim context",
    description:
      "Get the user's live Neovim editor state: current file and cursor, last visual selection, open buffers, and LSP diagnostics. Call this when the user refers to 'this file', 'here', 'the selection', 'this error', or what they are looking at.",
    parameters: pi.zod.object({}),
    async execute(_toolCallId, _params, _signal, _onUpdate, _ctx) {
      try {
        const res = Bun.spawnSync(
          [nvimBin, "--server", server, "--remote-expr", expr("context")],
          {
            timeout: 3000,
            env: { ...process.env, NVIM_APPNAME: "bide" },
          },
        );
        const stdout = res.stdout ? res.stdout.toString().trim() : "";
        if (res.exitCode !== 0 || !stdout) {
          return {
            content: [
              {
                type: "text",
                text: "Neovim did not respond (is it blocked on a prompt?)",
              },
            ],
            details: {},
            isError: true,
          };
        }
        return {
          content: [{ type: "text", text: stdout }],
          details: { bytes: res.stdout.byteLength },
        };
      } catch {
        return {
          content: [
            {
              type: "text",
              text: "Neovim did not respond (is it blocked on a prompt?)",
            },
          ],
          details: {},
          isError: true,
        };
      }
    },
  });
}
