# Current State

## Status
Destination-assignment and character-needs loop implemented and passing the
Godot 4.6.2 headless startup/parse check.

## What Exists

- A procedurally built 3D town with NPC speech/text conversations, pointing
  camera sequences, turn-by-turn directions, and discovery progress.
- A three-choice destination overlay after the intro and every completed
  assigned trip. The selected assignment appears in its own top-left HUD card.
- Assignment and navigation are separate: navigation begins only after a
  successful spoken or typed "Where is the &lt;place&gt;?" question to an NPC.
- Scripted thirst, hunger, and tiredness events that fire only after arrivals,
  bias the next choices to real town goals, resolve with a short reaction, and
  always leave normal trips between need trips.
- Optional NPC uncertainty. A refusing NPC points to a real nearby townsperson;
  the first destination question is safe and no more than two refusals can occur
  in a row.
- The existing discovery tracker, poster hints, welcome sign, first-arrival
  celebrations, revisits, and curiosity trips remain in place.

## Current Work
The scoped implementation is complete.

## Known Issues
The two new referral lines do not yet have pre-recorded clips. Web Speech is the
intentional fallback until clips are generated.

## Next Steps
Play-check the overlay, arrival cadence, and nearby-NPC referral presentation in
the interactive editor or web build.
