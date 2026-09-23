# Arena Bowl Game - Sprint 1 MVP

## Rocket League + Tanks Hybrid for Web Platforms

### Project Overview
Arcade vehicle combat game with kustomizirovannye mashinki, seamless arena, and physics-based gameplay.

---

## Sprint 1: Core Physics ✅

### Implemented Features

#### 1. Arcade Vehicle Controller (`arcade_vehicle_controller.gd`)
- **Physics Base**: RigidBody3D with raycast suspension (4 wheels)
- **Engine Parameters**:
  - `max_speed`: 45.0 m/s
  - `engine_force`: 80.0 N
  - `boost_multiplier`: 1.7x
  - `brake_force`: 120.0 N

- **Steering & Handling**:
  - Dynamic steering limit (reduces at high speed)
  - Drift mode with reduced grip (0.35 factor)
  - Lateral grip damping for controlled slides

- **Downforce System**:
  - Speed-proportional downforce for wall riding
  - Keeps vehicle stable on curved surfaces

- **Air Stabilization**:
  - Auto-leveling torque when airborne
  - Prevents chaotic flipping

#### 2. Seamless Bowl Arena (`seamless_bowl_arena.gd`)
- **Geometry**: Rounded bowl shape with no 90° angles
- **Fillet Radius**: 5.0m smooth transitions
- **Physics Material**:
  - Friction: 0.1 (low for sliding)
  - Restitution: 0.3 (moderate bounce)
- **Procedural Generation**: Mesh built from ring segments

#### 3. Dynamic Camera System (`dynamic_vehicle_camera.gd`)
- **Spring Arm**: 6.0m length, -15° angle
- **Smoothing**: Lerp-based following (0.12 speed)
- **Dynamic FOV**: 75° → 90° on boost
- **Look-ahead**: Camera leads in movement direction

#### 4. Game Manager (`game_manager.gd`)
- Scene coordination
- Vehicle spawning
- Input mapping
- Environment setup (toon shading style)

---

## File Structure

```
arena_bowl_game/
├── project.godot              # Godot 4.x project config
├── scenes/
│   └── main_game.tscn         # Main game scene
├── scripts/
│   ├── arcade_vehicle_controller.gd
│   ├── dynamic_vehicle_camera.gd
│   ├── seamless_bowl_arena.gd
│   ├── vehicle_scene.gd
│   └── game_manager.gd
├── assets/
│   ├── models/
│   └── textures/
└── README.md
```

---

## Controls

| Action | Key/Button |
|--------|------------|
| Accelerate | W / Up Arrow |
| Brake/Reverse | S / Down Arrow |
| Steer Left | A / Left Arrow |
| Steer Right | D / Right Arrow |
| Boost | Shift |
| Drift | Space |
| Fire | Ctrl (Sprint 2) |
| Reset Vehicle | R |
| Pause | Escape |

---

## Definition of Done (Sprint 1)

✅ Machine accelerates responsively with boost  
✅ Drift mechanic reduces lateral grip  
✅ Seamless arena walls (no 90° corners)  
✅ Vehicle maintains momentum along curved walls  
✅ Smooth camera follow without physics jitter  
✅ Dynamic FOV changes on boost  
✅ Code structured with spawn points & weapon hardpoints  

---

## Next Steps (Sprint 2)

- [ ] Combat mechanics (projectiles, hitscan)
- [ ] Health system & damage
- [ ] Power-ups (shield, speed, super-shot)
- [ ] Weapon hardpoint mounting
- [ ] Hitbox configuration

---

## Technical Notes

### Physics Layers
- Layer 1: Ground
- Layer 2: Environment
- Layer 3: Vehicles
- Layer 4: Projectiles (Sprint 2)
- Layer 5: Pickups (Sprint 2)

### Performance Targets
- 60 FPS on mid-range hardware
- Low-poly styling (vertex colors, simple materials)
- Efficient collision shapes

### Web Platform Compatibility
- Designed for Yandex Games, VK Direct Games, Telegram WebApp
- Offline-first architecture
- SDK integration ready (Sprint 4)

---

## Running the Project

1. Install Godot Engine 4.2+
2. Open `project.godot`
3. Press F5 to run

```bash
# Or use command line
godot --path /workspace/arena_bowl_game
```

---

## License
Open-source (MIT recommended for web platforms)
