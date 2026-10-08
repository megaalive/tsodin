# tsodin

> Yet another TypeScript checker/compiler — this time in Odin. The benchmarks can do the talking.

tsodin is an experimental, performance-first TypeScript checker/compiler implemented in Odin.

The project is intentionally early. There are no compatibility, conformance, or performance claims yet.

## Engineering doctrine

The core rule is:

> **Readable invariants, aggressive implementation.**

A slightly longer version:

> **Make semantics obvious. Make data compact. Make hot paths ruthless. Document every non-obvious reason. Measure everything.**

tsodin is not an ordinary application and will not blindly follow application-level "best practices". Smart or unusual implementation techniques are welcome when they are correct, measurable, and explainable.

AI may write code, but AI must never be the only place where the reason that code works is documented.

## Read before contributing

- [AGENTS.md](AGENTS.md) — fast repository/contributor map for humans and coding agents
- [Architecture](docs/ARCHITECTURE.md)
- [Memory model](docs/MEMORY.md)
- [Performance doctrine](docs/PERFORMANCE.md)
- [Benchmarking](docs/BENCHMARKING.md)
- [Hack registry](docs/HACKS.md)

## Current status

Repository initialized with engineering and maintenance rules before implementation begins.
