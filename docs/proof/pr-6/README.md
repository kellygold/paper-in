# Paper In 0.3.6 control-state evidence

Candidate: `20c1485956d4fe5e31fb469e24fe5db3e20ff0af`.

Native SwiftUI views rendered at a 920 × 740 window size using generated sample pages and blank fixtures. The harness uses the bundled provider catalog and a synthetic display-only output path. It creates no scanner jobs or AI requests; its temporary drafts are removed when it exits.

- `auto-long-controls.png`: long-receipt guidance and one-side selection.
- `auto-empty-controls.png`: both blank sides hidden, zero visible pages, Restore page available, and Save PDF disabled.

These screenshots prove layout and synthetic state rendering. Hardware AutoCrop acceptance, actual cropped dimensions and edge quality remain unvalidated. An inactive offscreen window renders some native controls grey.
