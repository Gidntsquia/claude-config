---
name: write-readme
description: Write or rewrite a repo's README in the user's short house style, move long technical detail to the GitHub wiki (cloned into a gitignored wiki/ folder), and create the GitHub repo if there isn't one. Use for any README request (new, rewrite, shorten, "less AI-sounding"). Args after /write-readme adjust the defaults.
---

# write-readme

Short README in the user's style + detail in the GitHub wiki, done in one pass. Read `references/style.md` before writing; it has the template, voice rules and the sentences the user rejected.

Args are adjustments ("no wiki", "private", "name it X", "gif is docs/foo.gif"). Apply them without asking.

## Steps

1. **Read.** `README.md`, the manifest (`package.json`/`pyproject.toml`/`Cargo.toml`) for run commands, `ls docs screenshots`, `ls LICENSE`, `git remote -v`, `gh auth status`. Skim the entry point if needed. Everything written must be true of the current code.

2. **GitHub repo.** If there's no `origin`, create it: `gh repo create <owner>/<name> --public --source . --remote origin --push` (public unless args say private; name = the project's name from the manifest/title in kebab-case, else the folder name). Then `gh repo edit --enable-wiki`.

3. **Wiki check, early.** `git ls-remote "https://github.com/<o>/<r>.wiki.git"`. If it fails, the wiki has never had a page (GitHub has no API to create one). Tell the user right away: "Open https://github.com/<o>/<r>/wiki/_new and click Save page", and keep working on steps 4-6 while they do it.

4. **Hero image.** Preference: a gif in `docs/`, an image the user names, the widest screenshot of the main screen. Look at candidates with Read. Copy it into `docs/` if its folder is gitignored. None at all: put `<!-- TODO: screenshot of X -->` at the top and say so. A second image is fine for a second major mode.

5. **README.** Template and voice from `references/style.md`, 60-90 lines. How-it-works detail (formulas, thresholds, internals, reasoning) goes to the wiki.

6. **License.** No LICENSE: add MIT (user's name, current year) and tell the user so they can remove it. Always include the License section.

7. **Wiki in `wiki/`.** Unless args say no wiki:
   - `git clone "https://github.com/<o>/<r>.wiki.git" wiki` in the repo root (retry once the user has saved the first page), and add `/wiki/` to `.gitignore` under a `# GitHub wiki clone (its own repo)` comment.
   - Split the old README/docs by heading into pages: `Title-Case-With-Dashes.md`, `# Title` first line, `###` promoted to `##`, text mostly verbatim. Write `Home.md` with one line per page. Delete the placeholder page the user made.
   - `git -C wiki add -A && git -C wiki commit && git -C wiki push --force origin HEAD:master` (force only to replace the placeholder; never over real pages).
   - Remove any `docs/*.md` the pages replace. Link every page from the README's Documentation section.
   - Fall back to `docs/` markdown only if the wiki can't be pushed at all; say why.

8. **Self-check**, then commit README, LICENSE, `.gitignore`, images and removed docs; push. Check each wiki page returns 200 (`curl -so /dev/null -w '%{http_code}'`). Report in a few lines: repo URL, what moved to which page, and that `wiki/` is a clone (edit, commit and push from inside it).

## Self-check

Reread the README for the tells in `references/style.md`. The two the user named: "not X, but Y" / "comes from Y, not Z" contrasts, and conversational filler ("actually", "really", "spits out", "nitty gritty", "that's it"). Rewrite tagline-like bullets as plain statements of what the software does.
