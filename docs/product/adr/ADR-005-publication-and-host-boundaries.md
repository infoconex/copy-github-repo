# ADR-005: Verify content before protection restoration and limit v0.1.0 to github.com

Status: Accepted

## Context

Repository protection can block initial publication if restored too early, while weakening protection merely for portability is unacceptable. Host behavior also varies across GitHub.com and GitHub Enterprise Server, especially for API capabilities, authentication, and settings/protection semantics.

## Decision

Destination content is published and verified first, ordinary supported settings are restored next, and transferable protection is restored last. Non-transferable protection is reported rather than weakened. v0.1.0 supports `github.com` only and fails closed for other hosts.

## Alternatives and tradeoffs

- Restore protection before content: preserves policy earlier but can prevent the intended initial publication.
- Weaken unsupported protection automatically: increases apparent portability but violates security semantics.
- Claim generic GitHub host support: broadens reach but creates an unvalidated compatibility contract.

## Consequences

Protection restoration is a distinct late mutation stage with its own partial-failure semantics. Host checks remain an explicit boundary. Future GitHub Enterprise Server support requires deliberate compatibility work rather than removal of the guard.