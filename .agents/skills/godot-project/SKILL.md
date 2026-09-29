---
name: sworm-vlood-godot
description: Use for GDScript, scenes, resources, shaders, and runtime checks in the SwormVlood Godot project.
---

# SwormVlood Godot work

- Read the affected scene, script, and nearby conventions before editing. Preserve unrelated work in `project.godot` and other files.
- The current local editor is Godot `4.8.dev5.mono`. Locate its console executable and verify `--version` before relying on version-specific behavior. README references 4.6.1; confirm the intended baseline before changing project compatibility.
- Check current Godot documentation for unfamiliar or version-sensitive APIs. Use the available documentation tools or official Godot docs; do not infer API names from old examples.
- Keep changes small and consistent with the project's GDScript style, scene structure, and existing components. Let Godot generate resource UIDs.
- After a change, use the Godot CLI from the project root for a relevant headless editor/import check, then run the affected scene or game when behavior or visuals matter. Report actual errors and warnings separately.
- Use an editor integration if available. If it is unavailable, use the Godot CLI and inspect the running application directly when needed.
