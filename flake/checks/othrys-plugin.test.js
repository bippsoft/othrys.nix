import { afterEach, beforeEach, expect, test } from "bun:test"
import { $ } from "bun"
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"

const { Othrys } = await import(join(process.env.OTHRYS_ROOT, ".opencode/plugins/othrys.js"))
const forbiddenDomain = "fixture.invalid"
const forbidden = "alice@" + forbiddenDomain
let root
let before

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "othrys-plugin-"))
  const hooks = await Othrys({ $, worktree: root })
  before = (tool, args) => hooks["tool.execute.before"]({ tool, sessionID: "fixture" }, { args })
})

afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

test("edit scans the address assembled from an existing local part", async () => {
  const filePath = join(root, "contact.txt")
  await writeFile(filePath, "alice@example.com\n")
  await expect(before("edit", { filePath, oldString: "example.com", newString: forbiddenDomain }))
    .rejects.toThrow("Refused by hygiene-scan")
  expect(await readFile(filePath, "utf8")).toBe("alice@example.com\n")
})

test("multiedit scans sequential replacements that assemble an address", async () => {
  const filePath = join(root, "contact.txt")
  await writeFile(filePath, "contact: PLACEHOLDER\n")
  await expect(before("multiedit", {
    filePath,
    edits: [
      { oldString: "PLACEHOLDER", newString: "alice@DOMAIN" },
      { oldString: "DOMAIN", newString: forbiddenDomain },
    ],
  })).rejects.toThrow("Refused by hygiene-scan")
})

test("replaceAll scans every occurrence with the tool's replacement expansion", async () => {
  const filePath = join(root, "contact.txt")
  await writeFile(filePath, "alice@PLACEHOLDER\nbob@PLACEHOLDER\n")
  await expect(before("edit", {
    filePath, oldString: "PLACEHOLDER", newString: forbiddenDomain, replaceAll: true,
  })).rejects.toThrow("Refused by hygiene-scan")
  await writeFile(filePath, forbiddenDomain + "\nalice@TOKEN\n")
  await expect(before("edit", {
    filePath, oldString: "TOKEN", newString: "$`", replaceAll: true,
  })).rejects.toThrow("Refused by hygiene-scan")
})

test("empty oldString overwrites rather than appending to existing contents", async () => {
  const filePath = join(root, "contact.txt")
  await writeFile(filePath, forbidden + "\n")
  await before("edit", { filePath, oldString: "", newString: "alice@example.com\n" })
})

test("safe exact edits and CRLF normalization are allowed", async () => {
  const filePath = join(root, "contact.txt")
  await writeFile(filePath, "alice@example.com\r\nlabel\r\n")
  await before("edit", { filePath, oldString: "example.com\nlabel", newString: "example.org\nlabel" })
})

test("ambiguous and unmatched edits are refused before scanning", async () => {
  const filePath = join(root, "contact.txt")
  await writeFile(filePath, "label\nlabel\n")
  for (const oldString of ["label", "missing"])
    await expect(before("edit", { filePath, oldString, newString: "safe" })).rejects.toThrow("Cannot reconstruct edit")
})

test("write scans the complete replacement file", async () => {
  await expect(before("write", { filePath: join(root, "contact.txt"), content: forbidden }))
    .rejects.toThrow("Refused by hygiene-scan")
  await before("write", { filePath: join(root, "contact.txt"), content: "alice@example.com\n" })
})

test("patch continues scanning additions after a Move to header", async () => {
  await writeFile(join(root, "before.txt"), "alice@example.com\n")
  await expect(before("apply_patch", { patchText: [
    "*** Begin Patch", "*** Update File: before.txt", "*** Move to: after.txt", "@@",
    "-alice@example.com", "+" + forbidden, "*** End Patch",
  ].join("\n") })).rejects.toThrow("Refused by hygiene-scan")
})

test("a move scans unchanged contents using the destination exemptions", async () => {
  await mkdir(join(root, "modules/services"), { recursive: true })
  await writeFile(join(root, "modules/services/ddns.nix"), forbidden + "\n")
  await expect(before("apply_patch", { patchText: [
    "*** Begin Patch", "*** Update File: modules/services/ddns.nix",
    "*** Move to: contact.txt", "*** End Patch",
  ].join("\n") })).rejects.toThrow("Refused by hygiene-scan")
})

test("patch scans unchanged contents when another line is edited", async () => {
  await writeFile(join(root, "contact.txt"), forbidden + "\nlabel\n")
  await expect(before("apply_patch", { patchText: [
    "*** Begin Patch", "*** Update File: contact.txt", "@@", "-label", "+updated label", "*** End Patch",
  ].join("\n") })).rejects.toThrow("Refused by hygiene-scan")
})

test("patch checks every added file and permits deletes", async () => {
  await expect(before("apply_patch", { patchText: [
    "*** Begin Patch", "*** Add File: safe.txt", "+alice@example.com",
    "*** Add File: contact.txt", "+" + forbidden, "*** End Patch",
  ].join("\n") })).rejects.toThrow("Refused by hygiene-scan")
  await writeFile(join(root, "contact.txt"), forbidden)
  await before("apply_patch", { patchText: "*** Begin Patch\n*** Delete File: contact.txt\n*** End Patch" })
})

test("exact skip-ahead, EOF and pure-addition chunks are allowed", async () => {
  await writeFile(join(root, "contact.txt"), "heading\nalice@example.com\nfooter\n")
  await before("apply_patch", { patchText: [
    "*** Begin Patch", "*** Update File: contact.txt", "@@ heading",
    "-alice@example.com", "+alice@example.org", "@@", "-footer", "+footer updated",
    "*** End of File", "@@", "+extra", "*** End Patch",
  ].join("\n") })
})

test("pure additions use the tool's trailing-blank insertion point without advancing the cursor", async () => {
  await writeFile(join(root, "contact.txt"), "label\n\n")
  const scans = []
  const shell = (strings, ...values) => {
    scans.push(values.at(-1).text())
    return { nothrow: () => ({ quiet: async () => ({ exitCode: 0 }) }) }
  }
  const hooks = await Othrys({ $: shell, worktree: root })
  await hooks["tool.execute.before"]({ tool: "apply_patch", sessionID: "fixture" }, {
    args: { patchText: [
      "*** Begin Patch", "*** Update File: contact.txt", "@@", "+extra",
      "@@", "-label", "+updated label", "*** End Patch",
    ].join("\n") },
  })
  expect(await Promise.all(scans)).toEqual(["updated label\nextra\n"])
})

test("patch applies all chunks before scanning, allowing removal of forbidden text", async () => {
  await writeFile(join(root, "contact.txt"), "first\nsecond\n")
  await before("apply_patch", { patchText: [
    "*** Begin Patch", "*** Update File: contact.txt", "@@", "-first", "+alice@",
    "@@", "-second", "+" + forbiddenDomain, "*** End Patch",
  ].join("\n") })
  await writeFile(join(root, "contact.txt"), forbidden + "\nlabel\n")
  await before("apply_patch", { patchText: [
    "*** Begin Patch", "*** Update File: contact.txt", "@@", "-" + forbidden,
    "+alice@example.com", "@@", "-label", "+updated label", "*** End Patch",
  ].join("\n") })
})

test("unrecognized patch formats and inexact context are refused", async () => {
  await writeFile(join(root, "contact.txt"), "  alice@example.com\n")
  for (const patchText of [
    "*** Begin Patch\n*** Update File: contact.txt\n@@\n-alice@example.com\n+safe\n*** End Patch",
    "*** Begin Patch\n*** Move to: contact.txt\n+safe\n*** End Patch",
    "unsupported",
  ]) await expect(before("apply_patch", { patchText })).rejects.toThrow("Cannot reconstruct patch")
})

test("relative paths resolve from the session directory, exemptions from the worktree", async () => {
  const directory = join(root, "nested")
  await mkdir(directory)
  await writeFile(join(directory, "contact.txt"), "alice@example.com\n")
  const hooks = await Othrys({ $, worktree: root, directory })
  await expect(hooks["tool.execute.before"]({ tool: "edit", sessionID: "fixture" }, {
    args: { filePath: "contact.txt", oldString: "example.com", newString: forbiddenDomain },
  })).rejects.toThrow("Refused by hygiene-scan")
})
