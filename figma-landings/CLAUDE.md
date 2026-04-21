# Figma Landings

Landing pages built from Figma designs for Altairika and FranchCamp brands.

## Critical Rules

- Communicate in Russian; code comments and variable names in English
- Never hardcode secrets — use macOS Keychain or env vars
- Never commit .env, *.key, *.pem files
- Push to main triggers auto-deploy via Coolify — test locally first
- Always check `git status` before committing
- Always bind web servers to `0.0.0.0`, not `127.0.0.1`

## Project Structure

```
sites/           — individual landing pages (each in its own subdirectory)
skills/figma/    — Figma MCP skill reference
docs/            — project documentation
```

## Workflow

1. Get Figma URL from designer
2. Use `get_figma_data` to extract layout and content as YAML
3. Use `download_figma_images` to download SVG/PNG assets
4. Implement HTML/CSS/JS in `sites/<landing-name>/`
5. Test locally, commit, push — Coolify deploys to land.altget.ru

## Deploy

- Domain: land.altget.ru
- Platform: Coolify (auto-deploy on push to main)
- Each landing lives in `sites/<name>/` with its own `index.html`

## Secrets

Figma API token: `security find-generic-password -a "figma" -s "figma-api-token" -w`

## Development

- Commit messages in English, concise
- After code changes, update `docs/README.md` in the same commit
- Semantic HTML, modern CSS (flexbox/grid), minimal JavaScript
- Mobile-first responsive design
- Optimize images before committing
