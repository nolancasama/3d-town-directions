# Design Decisions

This file records meaningful product, UX, visual, architectural, or behavioral decisions for this project.

For each significant decision, record:

- Date
- What was decided or changed
- Why
- Previous approach, if relevant
- Rejected alternatives, if useful

Only record decisions that may be useful to understand later.

Do NOT record:
- trivial UI adjustments
- routine bug fixes
- formatting changes
- mechanical refactors with no design consequence
- every individual code modification

Git is the source of truth for detailed code-change history.

A useful rule:

> If a future developer or AI could reasonably ask, "Why is it designed this way?", record the answer here.

## 2026-09-01 — Assigned destinations and scripted character needs

- The game now offers exactly three destinations after the intro and after each
  completed assigned trip. The player's selection becomes an assignment shown
  in a separate destination card; it is no longer completely free-form progress
  through any place.
- Assignment is deliberately separate from the GoalManager navigation target.
  Choosing a button does not start directions, the goal ring, or the timer. The
  player must still practice the target sentence, "Where is the &lt;place&gt;?",
  with an NPC before NPCInteraction starts navigation.
- The existing discovery tracker keeps the top-left corner. It is
  a parallel progress system for posters, signs, first discoveries, labels, and
  reveal icons, so replacing it with the current assignment would discard useful
  exploration feedback.
- Thirst, hunger, and tiredness use a scripted completed-trip schedule with
  small jitter instead of continuously decaying meters. This keeps the lesson
  rhythm predictable, prevents interruptions while walking, and avoids adding a
  survival-style interface.
- The town has no goal named Cafe. Coffee-shop references and thirst choices map
  to the real goal name **Starbucks**, which is also the name accepted by the
  speech matcher.

## 2026-09-01 — Destination HUD moved to top-centre; one redirect only

- The assigned-destination card moved from the top-left to a compact,
  translucent objective banner centred on the top edge. The top-left corner is
  the discovery tracker's, and stacking the two there pushed the tracker down
  and read as two competing panels. The banner is sized by its own content and
  centre-anchored, so it stays centred and compact at any window size, and it
  fades in over 0.18s so a new objective registers without delaying play.
- The elapsed timer moved down to clear the banner's height. Both are top-centre
  and both are visible while navigating, so a fixed offset keeps them apart.
- NPC refusals are capped at **one**. Previously two consecutive "I don't know"
  replies were allowed, which read as the game being broken rather than as
  natural uncertainty. After a single redirect the next townsperson always
  answers. Separately, a referral never points back at someone who has already
  refused for the current question — two NPCs were bouncing the player between
  each other.
- The two refusal lines are pre-recorded for every voice family. `speak()` falls
  back to browser TTS whenever a clip is missing, so a line without clips is
  audibly a different voice from the rest of that NPC's speech. Any new fixed
  NPC line must ship with clips in `assets/voice/{female,male}/` and the root
  (piper) set, or it will sound wrong.
- "Ask him." / "Ask her." carry a Japanese gloss under the English (彼 / 彼女),
  making the him/her distinction the line teaches explicit in both languages.
  The gloss is an optional third argument to `show_text()` for reuse elsewhere.
- The destination card's caption reads 行き先 rather than DESTINATION, in the
  Japanese font. The place names stay in English because they are the words the
  student has to say to an NPC.
- A one-time Japanese tutorial hint appears at the bottom after the very first
  destination is chosen, teaching the loop (choose -> approach someone -> ask).
  It is a notice, not a modal: it ignores mouse input and never freezes the
  player, and it fades as soon as the player walks up to any townsperson. The
  bottom-centre slot is safe because the directions panel that shares it only
  appears after an NPC has given directions, by which point the hint is gone.
- The discovered-places list is no longer permanently on the HUD. A compact
  counter (drawn map pin + "13 / 25") sits top-left and opens the full list on
  tap; the list closes on a second tap, the X, a click outside, or walking up to
  an NPC. This keeps the top-centre destination card the most prominent element
  and the counter clearly secondary.
- Found places are marked with a tick and dimmed slightly, replacing the old
  strikethrough, which read as "removed" or "unavailable" rather than "done".
  Unfound places stay bright, since those are the ones still worth going after.
- The list still shows only places the player has actually learned about, from
  posters and the town directory, plus anything discovered. It is not a reveal
  of all 25 goals -- that would undercut the poster/welcome-sign exploration.
- The counter icon is drawn vector art, not an emoji. The UI font is a subset of
  Noto Sans JP, which contains no pictographs, so any emoji renders as blank
  space in the web build (and silently falls back to a system font on Windows,
  which is why it looks fine in the editor).

