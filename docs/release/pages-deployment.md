---
title: "CopyGitHubRepo GitHub Pages Documentation Deployment"
description: "Understand how the CopyGitHubRepo Jekyll documentation site is built and deployed with GitHub Pages, including path filters, site inputs, exclusions, workflow permissions, concurrency, and validation."
---

# Documentation site deployment

The project website is published at `https://copy-github-repo.infoconex.com/` with Jekyll and GitHub Pages.

## Deployment model

The site is built and deployed by `.github/workflows/deploy-documentation-site.yml`, displayed in GitHub Actions as **Deploy Documentation Site**. The workflow is intentionally path-filtered so ordinary PowerShell implementation, test, and build-tool changes do not rebuild the website.

A manual deployment remains available through `workflow_dispatch`.

The Pages repository setting must use **GitHub Actions** as the publishing source. The workflow builds the site with GitHub's supported Jekyll Pages action, uploads the generated `_site` artifact, and deploys that artifact to the `github-pages` environment.

Pull requests do not deploy the public site. Documentation changes are checked separately by **Validate Documentation**, which runs the documentation contracts and builds/validates the generated site without publishing it.

## Custom-domain configuration and verification

The documentation domain is `https://copy-github-repo.infoconex.com/` and the Jekyll `baseurl` is empty: the homepage and CSS, JavaScript, images, sitemap, search index, and documentation paths all resolve from `/`, with no repository-name path prefix. The repository-root `CNAME` records `copy-github-repo.infoconex.com` for source visibility.

**GitHub Actions Pages deployment caveat:** this site uses GitHub Actions rather than branch-based Pages publishing. GitHub ignores the repository `CNAME` file for custom-domain configuration in this mode. The maintainer must configure **Settings → Pages → Custom domain** separately; the source file alone does not attach the hostname. Verify ownership of the custom domain before binding it, and ensure the domain is not attached to another GitHub Pages repository.

For this custom subdomain, the authoritative DNS provider should have a `CNAME` record for `copy-github-repo.infoconex.com` targeting `infoconex.github.io` (the account Pages host **without** a `/copy-github-repo` path, and not the parent `infoconex.com` apex domain). DNS is external to the repository and is not set by this deployment. Confirm DNS, GitHub Pages domain status, and certificate/HTTPS readiness independently; enable **Enforce HTTPS** once available.

After the domain is configured and the site is deployed, verify:

1. `https://copy-github-repo.infoconex.com/` serves the Jekyll homepage with HTTP success and the expected content.
2. `https://copy-github-repo.infoconex.com/assets/css/site.css`, `https://copy-github-repo.infoconex.com/assets/css/site-layout.css`, `https://copy-github-repo.infoconex.com/assets/js/site.js`, and the homepage image/search index load from the root (not from a `/copy-github-repo/` subpath).
3. Homepage and deep-page canonical URLs, Open Graph URLs, `sitemap.xml`, and `robots.txt` use the new host; the deployed-site smoke test checks the returned Pages URL and critical routes.
4. Former default Pages URLs redirect to the new hostname and preserve deep links, rather than becoming 404s. Check redirect behavior before removing old Search Console properties or changing external links.
5. Register/verify the new Search Console URL-prefix property and submit `https://copy-github-repo.infoconex.com/sitemap.xml`. Sitemap submission is not a guarantee of discovery or processing. Preserve the earlier Search Console evidence for comparison.
6. Update GitHub repository About link, and other outside-the-repository descriptions or links, manually. Future PowerShell Gallery packages use the updated module manifest; already published packages and their immutable metadata do **not** change when the source manifest changes.

Do not treat a passing repository build as proof that external DNS, GitHub Pages custom-domain binding, certificate readiness, redirect behavior, Search Console, or published PowerShell Gallery metadata have been updated. If cutover fails, fix DNS/Pages configuration or deliberately revert the site settings and matching Jekyll/manifest source through a reviewed change; do not silently publish mixed origin and base-path URLs.

## Site input surface

The following paths can affect the generated website and therefore trigger **Deploy Documentation Site**:

| Path | Purpose |
| --- | --- |
| `CNAME` | Custom-domain source declaration (Pages setting remains authoritative for Actions deployments) |
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
| `CNAME` | Yes |
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
