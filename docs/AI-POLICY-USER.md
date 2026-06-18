# Controlling AI bots for your site

Your sites are hosted behind a policy that sorts AI crawlers and assistants into
classes and decides, per class, whether to allow them. The defaults are sensible for
most sites, and you can change them for any individual site.

## What the defaults are

| AI traffic | Default | Meaning |
|------------|---------|---------|
| **Training** crawlers (GPTBot, ClaudeBot, CCBot, Bytespider, Amazonbot, …) | **Blocked** | Bots that harvest your content to train AI models are turned away. |
| **Search / index** bots (OAI-SearchBot, PerplexityBot, …) | **Allowed** | Bots that index your site so it can appear in AI search answers are let in (gently rate-limited). |
| **Assistant** fetchers (ChatGPT-User, Claude-User, …) | **Allowed** | When a person asks an AI assistant about a page on your site, that fetch is allowed. |
| **Utility** bots (read-aloud, ads, notebook tools) | **Allowed** | Allowed, rate-limited. |

Aggressive scrapers, download tools and obvious credential probes are always blocked and
are not configurable — that protection is on for every site.

## Changing it for a site

In the Octopus instance that hosts the site, edit (create if missing) the file:

```
static/control/ai/policy.txt
```

On a typical box that is `/data/disk/<instance>/static/control/ai/policy.txt`, where
`<instance>` is the Octopus user (e.g. `o1`) that hosts the site — your administrator can
tell you which one. Add one line per site: the site name, then the changes you want.

| Flag | What it does |
|------|--------------|
| `train-allow` | **Allow** AI training crawlers for this site (overrides the default block) |
| `search-block` | **Block** AI search/index bots for this site |
| `user-block` | **Block** AI assistant fetchers for this site |
| `utility-block` | **Block** AI utility bots for this site |

You can combine flags on one line. A site with no line keeps the defaults above.

```
# static/control/ai/policy.txt

# A news site happy to be in AI training data:
news.example.com    train-allow

# A members-only shop that wants no AI bots indexing or fetching it:
shop.example.com    search-block user-block utility-block

# A blog that wants AI search but not the assistant "user" fetchers:
blog.example.com    user-block
```

Lines starting with `#`, and anything after a `#`, are ignored.

## When it takes effect

Changes are picked up automatically within about **two minutes** — no restart, no
ticket. To put a site back to the defaults, delete its line; the override is removed on
the next pass.

## What you can't change here

The always-on protections — scrapers/bad bots, forged opt-out tokens (a request
pretending to be `Google-Extended` or `Applebot-Extended`), and credential/dotfile
probes — are blocked for every site and are not adjustable from this file. If you have a
genuine case where one of those blocks a legitimate request, ask your administrator.
