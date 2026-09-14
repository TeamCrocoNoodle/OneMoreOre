# Procedural ore geometry

Generated entirely from `scripts/rock_geometry.gd` by `tools/build_ore_mesh_banks.gd`.
There are four irregular layouts for each of the seven stages, using seeds 12872–12875.

The compressed resources store CPU mesh arrays, convex hull points and the exact
socket / fracture geometry. GPU meshes and physics shapes are created incrementally
at runtime, then reused. They contain no rewards, upgrades or player state. Every
ore still rolls new gem locations, rarities, stone variations and special stones.

The format and profile signature reject stale geometry after radius / layer / shape
changes. Colors and themes are applied at runtime. If a matching bank is unavailable,
the procedural builder remains available.

Regenerate with:

```powershell
godot --headless --path . --script res://tools/build_ore_mesh_banks.gd
```
