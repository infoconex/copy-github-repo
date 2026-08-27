---
title: "CopyGitHubRepo GitHub Pages Documentation Deployment"
description: "Understand how the CopyGitHubRepo Jekyll documentation site is built and deployed with GitHub Pages, including path filters, site inputs, exclusions, workflow permissions, concurrency, and validation."
---

# Documentation site deployment

The project website is published at `https://infoconex.github.io/copy-github-repo/` with Jekyll and GitHub Pages.

## Deployment model

The site is built and deployed by `.github/workflows/deploy-documentation-site.yml`, displayed in GitHub Actions as **Deploy Documentation Site**. The workflow is intentionally path-filtered so ordinary PowerShell implementation, test, and build-tool changes do not rebuild the website.

A manual deployment remains available through `workflow_dispatch`.

The Pages repository setting must use **GitHub Actions** as the publishing source. The workflow builds the site with GitHub's supported Jekyll Pages action, uploads the generated `_site` artifact, and deploys that artifact to the `github-pages` environment.

Pull requests do not deploy the public site. Documentation changes are checked separately by **Validate Documentation**, which runs the documentation contracts and builds/validates the generated site without publishing it.

## Site input surface

The following paths can affect the generated website and therefore trigger **Deploy Documentation Site**:

| Path | Purpose |
| --- | --- |
| `_config.yml` | Jekyll configuration, plugins, site metadata, layout defaults, exclusions, and asset versioning |
| `_data/**` | Structured site data, including documentation navigation |
| `_layouts/**` | HTML layouts used to render Markdown pages |
| `assets/**` | Site CSS, JavaScript, and images |
| `docs/**` | Project documentation and command reference pages |
| `README.md` | Website home page |
| `CHANGELOG.md` | Published changelog |
| `CODE_OF_CONDUCT.md` | Published code of conduct |
| `CONTRIBUTING.md` | Published contributor guidance |
| `SECURITY.md` | Published security policy |
| `LICENSE` | Static license target linked from the published README |
| `.github/workflows/deploy-documentation-site.yml` | Deployment definition; workflow changes must validate by running the workflow |

This list is intentionally explicit. Do not replace it with a repository-wide `**/*.md` filter unless the site's publication model changes so that every Markdown file is an intentional site input.

## Excluded repository content

The Jekyll source remains the repository root because the website intentionally renders both top-level project documents and `docs/**`. `_config.yml` excludes implementation and tooling paths that should not be copied into the generated site, including:

- `build`
- `src`
- `tests`
- `tools`
- installer and uninstaller scripts
- the root PowerShell launcher
- PSScriptAnalyzer settings

When a new root-level file or directory is introduced, maintainers should decide whether it is an intentional website input. If it is not, add it to the Jekyll exclusion list when necessary and do not add it to the deployment workflow trigger paths.

## Trigger behavior

Representative expected behavior:

| Change | Documentation deployment |
| --- | --- |
| PowerShell source only | No |
| Tests only | No |
| Build tooling only | No |
| `docs/**` | Yes |
| `_data/**` | Yes |
| `_layouts/**` | Yes |
| `assets/**` | Yes |
| `_config.yml` | Yes |
| Published top-level project document | Yes |
| Deployment workflow definition | Yes |
| Manual `workflow_dispatch` | Yes |

## Security and reliability

The workflow follows the repository's GitHub Actions supply-chain policy by pinning third-party/GitHub-maintained actions to full commit SHAs. The build job receives read-only repository contents permission. The deploy job receives only the additional `pages: write` and `id-token: write` permissions required by GitHub Pages and deploys through the `github-pages` environment.

Documentation deployments use a dedicated concurrency group with `cancel-in-progress: true`. When a newer site change starts while an older deployment is still queued or running, the obsolete run is cancelled so compute is spent on the newest publishable state. Generated-site validation still runs before deployment, and the published-site smoke tests still run after the successful newest deployment.

Manual `workflow_dispatch` deployments use the same concurrency group. Starting a newer manual or push-triggered deployment therefore supersedes an older in-progress deployment rather than allowing stale site content to finish afterward.

## Maintaining the trigger list

Any change that introduces a new Jekyll data source, layout/include directory, static asset directory, generated documentation input, or published root document must update `.github/workflows/deploy-documentation-site.yml` in the same change. Conversely, files that cannot affect the generated site should not be added to the deployment trigger list.

When documentation validation inputs change, review `.github/workflows/validate-documentation.yml` at the same time so pull-request validation and main-branch deployment remain aligned where they should be, while retaining their intentionally different publication behavior.
