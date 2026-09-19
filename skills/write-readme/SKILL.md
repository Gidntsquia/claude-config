---
name: write-readme
description: Write or rewrite a repo's README.md in the user's house style (screenshot at the top, short plain-English description, Quickstart, Features, wiki links, License) and move any long technical detail out into the GitHub wiki. Use this whenever the user asks for a README, wants a README rewritten, shortened, cleaned up, made "less AI-sounding", or says a README should match their other repos. Also use it when a repo has no README yet and the user wants one. Optional args after `/write-readme` are tone or content adjustments (e.g. "no wiki, keep it in one file", "more formal", "skip the brawl part").
---

# write-readme

Turn whatever README exists (or none) into the user's standard short README, and park the detail in the wiki. The reference for the target style is `references/style.md`; read it before writing a word. It has the section template, the voice rules, and before/after examples of sentences the user rejected as "clearly AI generated".

Arguments after `/write-readme` are adjustments layered on top of the defaults below. Typical ones: "keep everything in the README, no wiki", "drop the license section", "more/less casual", "lead with X instead of Y", "the gif is at docs/foo.gif". Apply them; don't ask about them.

## Steps

1. **Read what's there.** `cat README.md` (may not exist), `package.json` / `pyproject.toml` / `Cargo.toml` for the run commands, `ls docs screenshots` for images, `git remote -v` for the GitHub URL, `ls LICENSE`. Skim the main entry point if the README doesn't say what the app does. Don't invent features; everything in the README has to be true of the code as it is.

2. **Pick the hero image.** The top of the README is a screenshot or gif of the main thing the app does. Order of preference: an existing gif in `docs/`, a screenshot the user names, the widest existing screenshot of the main screen. Look at the candidates with the Read tool before choosing. If `screenshots/` is gitignored, copy the chosen file(s) into `docs/` so they render on GitHub. If there is no image at all, leave a clearly marked `<!-- TODO: screenshot of X -->` at the top and tell the user; don't fake one. A second image is fine lower down if the app has a second major mode (see the deadlock example in the style reference).

3. **Write the README** using the template and voice in `references/style.md`. Aim for 60-90 lines. Anything that explains *how* something works internally (formulas, thresholds, pixel coordinates, the reasoning behind a parameter) goes to the wiki, not the README.

4. **Move detail to the wiki** unless told not to. The wiki is a separate git repo at `https://github.com/<owner>/<repo>.wiki.git`. Clone it into the scratchpad, split the old README's technical sections into pages (one page per topic, `Title-Case-With-Dashes.md`, `# Title` as the first line), write a `Home.md` index with one line per page, commit, push. Promote `###` to `##` inside pages since each page is its own document. Keep the old text mostly verbatim; the point is relocation, not rewriting. Then link every page from the README's Documentation section with a short dash-separated summary of what it covers. If the wiki clone fails (wiki disabled, no push access), say so and keep the detail in a `docs/` markdown file instead, linked the same way.

5. **License.** If the repo has no LICENSE and the user's other repos are MIT, add the same MIT file (copyright the user's name, current year) and mention that you did so they can remove it. Don't silently skip the License section.

6. **Commit** the README, the license, and any images copied into `docs/`, and push if the branch tracks a remote. Report what moved where in a few lines.

## Self-check before committing

Read the finished README once more looking only for the tells listed in `references/style.md` under "Sentences the user flagged". The two the user has called out by name:

- "X comes from Y, not from Z" / "not X, but Y" contrast framing. Just state what it is.
- Words that exist to sound conversational: "actually", "really", "spits out", "nitty gritty", "to keep myself honest", "that's it".

If a bullet reads like a marketing tagline, rewrite it as a plain statement of what the software does.
