# Security

## Reporting

Report suspected vulnerabilities in Pegify marketplace content to
**security@pegify.com**. Do not open a public issue for security reports.

## Repository rules

This repository is content only:

- No Pegify application source code.
- No secrets, API keys, tokens, certificates, or signing material.
- No source maps.
- No files larger than 2 MiB — publish binaries as release assets.

`Distribution guard` CI enforces the allowlist on every push and pull request.
If a commit contains something that does not belong here, rotate the exposed
credential first, then remove it from history.
