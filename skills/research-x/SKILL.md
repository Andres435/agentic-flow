---
name: research-x
description: Search X (Twitter) with the built-in search-x verb. No X API, no bearer token. Use on spikes when current discussion would change the answer.
keywords: x, twitter, search, premium, spike, research
disable-model-invocation: false
icon: search
color: cyan
---

# Research X

Use the `search-x` verb ([harness-verbs](../../_shared/harness-verbs.md)). Do not call an X API,
do not add a bearer token, and do not add an MCP Twitter server.

## Handle

Read `user/identity.local.json` `xHandle` when that file exists (gitignored; shape in [identity.example.json](../../user/identity.example.json)). An empty
handle means search openly. Create that file and fill the handle once (never in the tracked example) if the question is about the user's own posts.

## When

A spike or `/start-ticket` tech spike whose question needs current public discussion. Optional.
Never a close gate. Skip when the question is answered from the repo.

## How

1. One sentence for what to find.
2. If the question is about the user's posts and `xHandle` is set, restrict the search to that
   handle. Otherwise search openly.
3. Cite the post links in the plan or spike page. Do not paste long threads.

## Do not

- Invent an API key or scrape beyond `search-x`.
- Treat Premium as a Cursor model-tier change. This skill is X search only.
