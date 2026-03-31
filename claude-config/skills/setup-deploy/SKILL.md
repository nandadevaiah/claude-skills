---
name: setup-deploy
version: 1.0.0
description: |
  One-time deploy configurator for /land-and-deploy. Detects platform
  (Fly.io, Render, Vercel, Netlify, Heroku, GitHub Actions, custom),
  production URL, health checks, and deploy commands. Saves config
  to CLAUDE.md. Use when: "setup deploy", "configure deployment",
  "set up CI/CD", "how do I deploy".
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - AskUserQuestion
---

# /setup-deploy — Deploy Configuration

One-time setup for the `/land-and-deploy` and `/canary` skills.
Detects your deployment platform and saves the configuration.

## Step 1: Auto-detect platform

```bash
# Check for platform-specific files
[ -f fly.toml ] && echo "PLATFORM:fly"
[ -f render.yaml ] && echo "PLATFORM:render"
[ -f vercel.json ] && echo "PLATFORM:vercel"
[ -f netlify.toml ] && echo "PLATFORM:netlify"
[ -f Procfile ] && echo "PLATFORM:heroku"
[ -f app.yaml ] || [ -f app.yml ] && echo "PLATFORM:gcp"
[ -f Dockerfile ] && echo "PLATFORM:docker"
ls .github/workflows/*.yml 2>/dev/null | head -5 && echo "PLATFORM:github-actions"
ls .gitlab-ci.yml 2>/dev/null && echo "PLATFORM:gitlab-ci"
```

## Step 2: Gather configuration

If auto-detected, confirm with user. If not detected, ask:

- **Platform:** How is the app deployed?
  - A) Vercel B) Fly.io C) Render D) Netlify E) Heroku
  - F) GitHub Actions G) GitLab CI H) Docker/K8s I) Custom/Manual

- **Production URL:** What's the production URL?
- **Health endpoint:** Does the app have a health check endpoint? (default: `/health` or `/`)
- **Deploy trigger:** How is deploy triggered?
  - A) Auto-deploy on merge to main
  - B) Manual deploy command
  - C) CI/CD pipeline
- **Deploy command** (if manual): What command deploys the app?
- **Typical deploy time:** How long does a deploy usually take? (default: 2-5 minutes)

## Step 3: Save configuration

Append deploy configuration to `CLAUDE.md`:

```markdown
## Deploy configuration

- **Platform:** <platform>
- **Production URL:** <url>
- **Health endpoint:** <url>/health
- **Deploy trigger:** auto-deploy on merge | manual
- **Deploy command:** <command> (if manual)
- **Typical deploy time:** <N> minutes
- **Monitoring pages:** /, /dashboard, /api/health
```

## Step 4: Verify

Test the health endpoint:
```bash
curl -sf -w "\nHTTP %{http_code} in %{time_total}s" <health-url>
```

Report whether the endpoint is reachable and healthy.

Tell the user: "Deploy configuration saved to CLAUDE.md. You can now use `/land-and-deploy` and `/canary`."
