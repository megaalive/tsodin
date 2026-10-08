#!/usr/bin/env node
// Version registry for external TypeScript CLI oracles. No compiler API required.
import { readFileSync } from "node:fs";
import { resolve, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(new URL("../..", import.meta.url)));
const registry = JSON.parse(readFileSync(join(root, "tests/oracle/profiles.json"), "utf8"));

export function loadOracleProfile(id = registry.defaultProfile) {
  if (registry.schemaVersion !== 1 || !Array.isArray(registry.profiles)) {
    throw new Error("Unsupported oracle profile registry");
  }
  if (new Set(registry.profiles.map(p => p.id)).size !== registry.profiles.length) {
    throw new Error("Duplicate oracle profile ID");
  }
  if (typeof id !== "string" || !/^[a-z][a-z0-9-]+$/.test(id)) {
    throw new Error("Unsafe oracle profile ID");
  }
  const profile = registry.profiles.find(p => p.id === id);
  if (!profile) throw new Error("Unregistered oracle profile: " + id);
  if (!/^\d+\.\d+\.\d+$/.test(profile.version) ||
      profile.npmSpec !== "typescript@" + profile.version ||
      profile.executable !== "tsc" ||
      !/^[0-9a-f]{40}$/.test(profile.upstreamCommit) ||
      !/^tests\/oracle\/[a-z0-9/-]+\.json$/.test(profile.manifest) ||
      !Array.isArray(profile.projectArguments) ||
      !profile.projectArguments.every(arg => typeof arg === "string" && /^[\w.\/-]+$/.test(arg))) {
    throw new Error("Invalid or unpinned oracle profile " + id);
  }
  return profile;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const command = process.argv[2];
  const id = process.argv[3];
  const profile = loadOracleProfile(id);
  if (command === "npmSpec") console.log(profile.npmSpec);
  else if (command === "executable") console.log(profile.executable);
  else if (command === "version") console.log(profile.version);
  else if (command === "manifest") console.log(profile.manifest);
  else throw new Error("Usage: node tools/oracle/profile.mjs npmSpec|executable|version|manifest profile-id");
}
