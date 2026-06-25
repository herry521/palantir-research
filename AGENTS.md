# AGENTS.md

These instructions apply to the entire `palantir-research` repository.

## Code Management Defaults

- Use GitLab EE as the default code management remote for this repository.
- Treat `origin` as the default remote and keep it pointed at GitLab EE.
- Only interact with GitHub when explicitly requested, and specify the `github` remote or GitHub repository target directly.

## Research Output Rules

- All research outputs must include 3 to 5 summary points or insights.
- Place the summary or insights near the beginning of the document or response.
- Keep each point specific and decision-relevant; mark facts, inferences, or speculation when the distinction matters.
- Important research conclusions must be saved to a repository file, not only returned in chat. If the user does not specify a path, create or update an appropriately named Markdown file under the nearest relevant docs or research directory.
