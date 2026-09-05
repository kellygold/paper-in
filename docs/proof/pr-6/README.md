# Paper In 0.3.7 control-state evidence

Candidate: `43a1135033cb260ee0f07d624a9af3aa4a980012`.

Native SwiftUI views rendered at a 920 × 740 window size using generated sample pages and blank fixtures. The harness uses the bundled provider catalog and a synthetic display-only output path. It creates no scanner jobs or AI requests; its temporary drafts are removed when it exits.

- `auto-long-controls.png`: long-receipt guidance and one-side selection.
- `auto-empty-controls.png`: both blank sides hidden, zero visible pages, Restore page available, and Save PDF disabled.

These screenshots prove layout and synthetic state rendering. Hardware AutoCrop acceptance, actual cropped dimensions and edge quality remain unvalidated. An inactive offscreen window renders some native controls grey.
