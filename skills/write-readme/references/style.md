# README style reference

The user's README voice, taken from their repos (pogo-gbl-team-generator, pokemon-go-video-to-csv,
MRC-ARL_Nav_Team) and from the corrections they gave while rewriting deadlock-build-optimizer.

## Template

```
# Project Name <one emoji>

<p align="center">
  <img alt="<what the picture shows, as a sentence>" src="docs/<file>.png|gif">
</p>

<2-5 sentences: what it does, what it's built on / where the data comes from, one
distinguishing detail. Link the game/site/library it's for. Plain description, not a pitch.>

<Optional: one more paragraph + image for a second major mode of the app.>

## Quickstart 🚀

<Requirements in one line, e.g. "Requires Node 18+.">

```
git clone https://github.com/<owner>/<repo>
cd <repo>
<install / setup>   # comment saying what it does and anything surprising (time, size, "needed after every fresh clone")
<run>               # Open http://localhost:xxxx
```

<1-3 sentences on what happens next / how to use the main screen. An
"IMPORTANT:" line for any gotcha that will bite a first-time user.>

Other commands:

```
<2-4 other invocations with trailing # comments>
```

## Features 🔬

- <6-10 bullets. Each is one or two plain sentences saying what the software does.>

## Documentation 📚

More details in the
[wiki](https://github.com/<owner>/<repo>/wiki):

- [Page Title](https://github.com/<owner>/<repo>/wiki/Page-Title) — three to six words on what it covers
- ...

## License 📄

[MIT](LICENSE). <One sentence on third-party data/engines that are downloaded rather than distributed.>
```

Section emoji are fixed: 🚀 Quickstart, 🔬 Features (or "What it does"), 📚 Documentation, 📄 License.
Title emoji is whatever fits the project. Use a single emoji per heading, no more.

Numbered steps in Quickstart are fine when the user has to do something outside the terminal first
(record a video, turn on a switch) before running commands.

## Voice

- Plain, direct, first person where it's natural ("the four players I check against"). Neutral
  register: not corporate, not chummy. The MRC-ARL README is the ceiling for casualness
  (an exclamation mark or two, "Note:", "IMPORTANT:"), and even that is more casual than the
  user wants for a public tool repo.
- Say what the thing does. Don't sell it and don't explain why it's clever; that goes in the wiki.
- One idea per bullet, one or two sentences. Bullets don't need parallel structure or a bolded lead-in.
- Features are things a user notices, not implementation facts. "Items past your usual final net
  worth are marked as stretch items" is a feature; "12-14 items, 3+ tier-1, at most 3 actives" and
  "scored within tier with a counter term and synergy" are spec and belong in the wiki. Numbers in the
  Features list should be results (agreement %, hero count), not parameters.
- The intro is 2-5 sentences and stays at the level of "what it does and where the data comes from".
  Validation numbers and mode-specific details go in Features or the wiki.
- Numbers are fine when concrete and useful ("~3 min, ~16 MB", "64-75% agreement"). Use a plain
  hyphen for ranges, `%` right after the number.
- Code-block comments start with a capital letter and read like a note to a friend
  ("Downloads pvpoke's engine + data (required after every fresh clone)").
- Contractions are fine ("doesn't", "aren't", "you've").
- An "IMPORTANT:" line in caps is the user's own idiom for a real gotcha. Use at most one.
- Em-dashes only in the Documentation list separators. Nowhere else.

## Sentences the user flagged as AI-generated, with the fix

| Rejected | Why | Replacement |
|---|---|---|
| Buy order comes from when people actually buy each item in real games, not from cost. | "not from X" contrast framing plus "actually" | Items are ordered by the average time players buy them at. |
| Once the data is fetched the app doesn't touch the network at all. | "at all" for emphasis, "touch" | After the data is downloaded the app doesn't make any network requests. |
| To keep myself honest, every build gets graded against a real top player | fake-humble aside | Each build is also compared to the recent games of a top player on that hero so you can see how close it gets. |
| Pick a hero and this spits out a build for it | forced casual verb | Generates an item build for any Deadlock hero: the items, the order to buy them in, and the ability level-up order. |
| Street Brawl: reads the three cards ... straight off the screen. Nothing is sent to the game, it only looks at pixels. | "straight off", trailing reassurance clause | Street Brawl: the cards, round number, enemy heroes, and the items you've already picked are all read from the screen. Nothing is sent to the game. |
| The nitty gritty is in the wiki | idiom for flavour | More details in the wiki: |
| That's it for builds, just click a hero. | filler | Click a hero to see its build. |
| Right now that's 64-75% agreement across the four players I check against, and the app shows you exactly which of their core items it missed. | "Right now that's", "exactly" | The four players I check against currently get 64-75% agreement, and the app lists the items from their core set that the build is missing. |
| Every weight I changed and why, with the numbers | punchy triad | the weight changes and the reasoning behind them |

General tells to strip:
- "not X, but Y" / "X, not Y" contrasts
- "actually", "really", "exactly", "at all", "simply", "just" as emphasis
- Parallel three-part bullets or "A → B → C" arrows
- Colon taglines at the start of bullets ("**Deterministic:** ...")
- Asides that perform a personality ("to keep myself honest", "nitty gritty")
- Closing reassurance clauses ("so you never have to worry about ...")

## Worked example: deadlock-build-optimizer

Before: a 370-line README with the scoring formula, pixel coordinates, held-out tables, and a
"Judgment calls" log inline.

After: an 83-line README (template above) plus eight wiki pages:
Data-Pipeline, How-the-Build-Generator-Works, Held-out-Validation, Street-Brawl-Advisor,
Screen-Reader, Overlay-and-Phone-Display, Judgment-Calls, Development. The old text was split by
`##`/`###` heading with `sed -n 'a,bp'` and pasted into pages nearly verbatim; each page got a
one-line lead naming the source files. The final README is at
https://github.com/Gidntsquia/deadlock-build-optimizer/blob/main/README.md; the two Pokemon GO
repos are the other two examples of the finished style.
