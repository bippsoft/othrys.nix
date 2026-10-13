// .opencode/plugins/othrys.js
// Two automatic steps for a session in this repository. Neither calls a model.
//
// Before a write, the text bound for each file goes through hygiene-scan, and
// a refusal stops the write. After a write in a session that edited a module,
// module-coverage runs, and a missing check or page is added to the result of
// that write, once for each distinct report.
//
// Both commands come from the dev shell. Imports are runtime built-ins, so
// OpenCode has no dependencies of this plugin's to install.

import { readFile } from "node:fs/promises"
import { resolve, relative } from "node:path"

const WRITERS = new Set(["write", "edit", "multiedit", "apply_patch", "patch"])

// Refuse fuzzy matches rather than scanning a different result from the tool.
function replace(text, edit) {
  if (typeof edit.oldString !== "string" || typeof edit.newString !== "string")
    throw new Error("Cannot reconstruct edit. oldString and newString must be strings.")
  if (edit.oldString === "") return edit.newString
  const ending = text.includes("\r\n") ? "\r\n" : "\n"
  const normalize = (value) => value.replaceAll("\r\n", "\n").replaceAll("\n", ending)
  const old = normalize(edit.oldString)
  const next = normalize(edit.newString)
  const index = text.indexOf(old)
  if (index === -1 || (!edit.replaceAll && index !== text.lastIndexOf(old)))
    throw new Error("Cannot reconstruct edit. Use an exact, unique oldString or replaceAll.")
  return edit.replaceAll ? text.replaceAll(old, next) : text.slice(0, index) + next + text.slice(index + old.length)
}

function update(text, body) {
  const lines = text.split("\n")
  if (lines.at(-1) === "") lines.pop()
  const replacements = []
  let cursor = 0
  let i = 0
  const find = (pattern, eof = false) => {
    const matches = (at) => pattern.every((line, j) => lines[at + j] === line)
    const end = lines.length - pattern.length
    if (eof && end >= cursor && matches(end)) return end
    for (let at = cursor; at <= end; at++) if (matches(at)) return at
    throw new Error("Cannot reconstruct patch. Use exact context and removed lines.")
  }
  while (i < body.length) {
    const header = body[i++]
    if (header !== "@@" && !header.startsWith("@@ "))
      throw new Error("Cannot reconstruct patch. Each update chunk must start with @@.")
    const context = header.slice(2).trim()
    if (context) cursor = find([context]) + 1
    const old = []
    const next = []
    let eof = false
    while (i < body.length && !body[i].startsWith("@@")) {
      const line = body[i++]
      if (line === "*** End of File") {
        eof = true
        break
      }
      if (line.startsWith(" ")) {
        old.push(line.slice(1))
        next.push(line.slice(1))
      } else if (line.startsWith("-")) old.push(line.slice(1))
      else if (line.startsWith("+")) next.push(line.slice(1))
      else throw new Error("Cannot reconstruct patch. Invalid update line.")
    }
    const at = old.length ? find(old, eof) : lines.at(-1) === "" ? lines.length - 1 : lines.length
    replacements.push({ at, count: old.length, next })
    if (old.length) cursor = at + old.length
  }
  replacements.sort((a, b) => a.at - b.at)
  for (const { at, count, next } of replacements.reverse()) lines.splice(at, count, ...next)
  if (lines.length === 0 || lines.at(-1) !== "") lines.push("")
  return lines.join("\n")
}

async function prospective(tool, args, directory) {
  if (["write", "edit", "multiedit"].includes(tool) && !args.filePath)
    throw new Error("Cannot reconstruct write. Missing filePath.")
  const path = resolve(directory, args.filePath ?? ".")
  if (tool === "write") {
    if (typeof args.content !== "string") throw new Error("Cannot reconstruct write. Missing content.")
    return [{ path, text: args.content }]
  }
  if (tool === "edit" || tool === "multiedit") {
    const edits = tool === "edit" ? [args] : args.edits
    if (!Array.isArray(edits) || edits.length === 0) throw new Error("Cannot reconstruct multiedit. Missing edits.")
    let text = edits[0].oldString === "" ? "" : await readFile(path, "utf8")
    for (const edit of edits) text = replace(text, edit)
    return [{ path, text }]
  }

  const lines = String(args.patchText ?? "").trim().split("\n")
  if (lines.shift() !== "*** Begin Patch" || lines.pop() !== "*** End Patch")
    throw new Error("Cannot reconstruct patch. Missing Begin/End markers.")
  const out = []
  while (lines.length) {
    const header = lines.shift().match(/^\*\*\* (Add|Update|Delete) File: (.+)$/)
    if (!header) throw new Error("Cannot reconstruct patch. Invalid file header.")
    const source = resolve(directory, header[2].trim())
    let target = source
    if (header[1] === "Update" && lines[0]?.startsWith("*** Move to: "))
      target = resolve(directory, lines.shift().slice("*** Move to: ".length).trim())
    const body = []
    while (lines.length && (!lines[0].startsWith("*** ") || lines[0] === "*** End of File"))
      body.push(lines.shift())
    if (header[1] === "Delete") {
      if (body.length) throw new Error("Cannot reconstruct patch. Delete has a body.")
      out.push({ path: source, text: null })
    } else if (header[1] === "Add") {
      if (body.some((line) => !line.startsWith("+"))) throw new Error("Cannot reconstruct patch. Invalid addition.")
      out.push({ path: target, text: body.length ? body.map((line) => line.slice(1)).join("\n") + "\n" : "" })
    } else {
      out.push({ path: target, text: update(await readFile(source, "utf8"), body) })
      if (target !== source) out.push({ path: source, text: null })
    }
  }
  return out
}

export const Othrys = async ({ $, worktree, directory = worktree }) => {
  const have = (name) => Bun.which(name) !== null
  const ready = have("hygiene-scan") && have("module-coverage")

  // Sessions that wrote under modules/, and the last reminder each was given.
  const touchedModules = new Set()
  const reminded = new Map()

  return {
    "tool.execute.before": async (input, output) => {
      if (!WRITERS.has(input.tool)) return
      if (!ready)
        throw new Error(
          "hygiene-scan is not on PATH. Start OpenCode inside `nix develop` so that writes can be scanned.",
        )

      for (const { path, text } of await prospective(input.tool, output.args ?? {}, directory)) {
        const target = relative(worktree, path)
        if (target.startsWith("modules/")) touchedModules.add(input.sessionID)
        if (!text) continue
        const scan = await $`hygiene-scan - ${target} < ${new Response(text)}`.nothrow().quiet()
        if (scan.exitCode !== 0)
          throw new Error(
            "Refused by hygiene-scan. This repository is public, see Public Hygiene in AGENTS.md.\n" +
              scan.stderr.toString(),
          )
      }
    },

    "tool.execute.after": async (input, output) => {
      if (!ready || !WRITERS.has(input.tool) || !touchedModules.has(input.sessionID)) return

      const coverage = await $`module-coverage`.cwd(worktree).nothrow().quiet()
      const report = coverage.stdout.toString().trim()
      if (coverage.exitCode === 0) {
        reminded.delete(input.sessionID)
        return
      }
      if (reminded.get(input.sessionID) === report) return
      reminded.set(input.sessionID, report)
      output.output =
        String(output.output ?? "") +
        "\n\nmodule-coverage reports that this branch is not finished:\n" +
        report +
        "\nA module change is finished when its check and its page changed with it. " +
        "Write what is missing before you stop, or say why this change needs neither."
    },
  }
}
