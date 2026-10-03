# Attributions

Codex94 is an independent implementation. It does not copy source code from the
projects below, but their public designs and process-integration approaches
informed the project. They are references, not bundled dependencies; no source
files, icons, or other assets from them are redistributed by Codex94.

- [claude-codex-battery](https://github.com/dennykim123/claude-codex-battery)
  inspired the compact, monospaced `% left` presentation and segmented quota
  bars. License: MIT.
- [codex-usage-bar](https://github.com/CMMUU/codex-usage-bar) demonstrated using
  Codex `app-server` account methods without reading credentials directly.
  License: MIT.
- [CodexBar](https://github.com/steipete/CodexBar) informed process hardening,
  bounded output, request timeout, cleanup choices and multi-provider quota
  presentation. [MIT license verified at commit
  `2cfa63250079b96b00a0da10358001e676cee19d`](https://github.com/steipete/CodexBar/blob/2cfa63250079b96b00a0da10358001e676cee19d/LICENSE).
- [Claude Code Usage Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor)
  is a design reference for distinguishing reported quota from estimates and
  making data freshness clear.
- [ccusage](https://github.com/ccusage/ccusage) is a reference for possible future
  local token/cost analytics. It is not used as a Claude quota source or bundled
  dependency; Claude token/cost analytics are not implemented in 4.0.

Codex and ChatGPT are trademarks of OpenAI; Claude and Claude Code are Anthropic
products. Codex94 is not affiliated with, endorsed by, or sponsored by either
company. The Codex94 icon and interface use original project assets and system
symbols, not the OpenAI or Anthropic logos. See the current
[OpenAI design guidelines](https://openai.com/brand/) for trademark terms.
