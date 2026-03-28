# Voxel Extraction

A **voxel PvE extraction game** built with [Godot Engine](https://godotengine.org/).

Drop into procedurally generated voxel worlds. Loot. Fight. Extract — or lose everything.

## What is this?

- **PvE extraction** — co-op raids against AI enemies, no PvP toxicity
- **Destructible voxel terrain** — blow holes in walls, collapse tunnels, reshape the battlefield
- **Loot and extract** — risk vs reward. Carry more = move slower. Die = lose it all
- **Timed raids** — 15 minutes. Extract before time runs out or everything is gone
- **AI-generated assets** — voxel art pipeline powered by ComfyUI + local AI

## Tech Stack

- **Engine:** Godot 4.6+ (open source)
- **Voxel System:** [godot_voxel](https://github.com/Zylann/godot_voxel) by Zylann
- **Art:** Blockbench / MagicaVoxel + ComfyUI for textures
- **Audio:** Original soundtrack and SFX

## Controls

| Key | Action |
|-----|--------|
| WASD | Move |
| Shift | Sprint |
| Space | Jump |
| E | Interact |
| F | Extract (in zone) |
| Tab | Inventory |
| LMB | Attack |
| RMB | Aim |

## Building

Requires Godot 4.6+ with the godot_voxel module.

```bash
# Install Godot
sudo pacman -S godot

# Clone
git clone https://github.com/bong-water-water-bong/voxel-extraction.git
cd voxel-extraction

# Open in Godot
godot --editor project.godot
```

## Project Structure

```
voxel-extraction/
├── assets/          # Textures, models, sounds, music, UI, shaders
├── scenes/          # Godot scenes (world, player, enemies, items, UI)
├── scripts/         # GDScript source
│   ├── player/      # Player controller, inventory, HUD
│   ├── enemies/     # Enemy AI, spawning, behaviors
│   ├── world/       # Voxel generation, chunks, extraction zones
│   ├── items/       # Loot, pickups, weapons
│   ├── systems/     # Game manager, extraction, loot tables, audio
│   ├── ui/          # Menus, HUD, inventory UI
│   └── network/     # Co-op multiplayer
├── addons/          # Godot plugins (godot_voxel)
└── docs/            # Design docs, lore, art guides
```

## License

Open source. License TBD.

---

Part of the [halo-ai](https://github.com/bong-water-water-bong/halo-ai) ecosystem.
