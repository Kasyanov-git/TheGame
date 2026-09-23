# Arena Bowl Game - Sprint 2: Combat & Perks

## Overview
Sprint 2 implements the complete combat system with mountable weapons, health/damage mechanics, and arena pickups.

## New Components (Sprint 2)

### 🎯 Weapon System

#### `BaseWeapon` (`scripts/weapons/base_weapon.gd`)
Abstract base class for all weapons with:
- Turret aiming with rotation speed limits (12 rad/s)
- Pitch constraints (-10° to +30°)
- Fire rate, damage, spread, ammo management
- Mouse-look aiming via camera raycast
- Signals: `weapon_fired`, `weapon_reloaded`

#### `ProjectileWeapon` (`scripts/weapons/projectile_weapon.gd`)
Fast projectile weapon (main cannon):
- Projectile speed: 120 m/s
- Lifetime: 3.0s
- Large trigger collider (0.8m radius) for easy hits
- Optional explosion splash damage
- Auto-generated projectile with physics

#### `HitscanWeapon` (`scripts/weapons/hitscan_weapon.gd`)
Instant hitscan weapon (machine gun):
- Range: 300m
- Damage falloff from 150m to 300m
- Hit marker effects
- Raycast-based instant damage

### ❤️ Health & Damage

#### `HealthComponent` (`scripts/components/health_component.gd`)
Modular health system:
- Max HP: 100 (configurable)
- Respawn delay: 4.0s
- Invincibility after spawn: 2.0s
- Signals: `health_changed`, `hit_registered`, `on_vehicle_destroyed`, `on_vehicle_respawned`
- Methods: `take_damage()`, `heal()`, `apply_shield()`
- Auto-disables physics/mesh on death

### 🎁 Arena Pickups

#### `PickupBase` (`scripts/pickups/pickup_base.gd`)
Power-up spawn points with 5 types:
1. **Nitro** - Refills 100% boost
2. **Health** - Restores +35 HP
3. **Shield** - 6s invincibility bubble
4. **SpeedBoost** - 1.3x speed for 5s
5. **DamageBoost** - 1.5x damage for 5s

Features:
- Cooldown: 10s respawn timer
- Rotating icon visuals
- Collect/respawn effects
- Signals: `pickup_collected`, `pickup_respawned`

### 🚗 Combat Vehicle Integration

#### `CombatVehicle` (`scripts/entities/combat_vehicle.gd`)
Integrates movement, weapons, and health:
- Boost management (drain/regen)
- Weapon switching (number keys)
- Temporary buff application
- Team ID support
- Bot/player distinction
- Signals for UI integration

## Updated Components

### `ArcadeVehicleController` (Updated)
Added support for:
- `set_boost_active()` - Called by CombatVehicle
- `set_speed_multiplier()` - For SpeedBoost pickup
- `get_effective_max_speed()` - Accounts for buffs

## Scene Setup Instructions

### Creating a Combat Vehicle

```
CombatVehicle (Node3D)
├── ArcadeVehicleController (RigidBody3D)
│   ├── MeshContainer (Node3D)
│   │   └── [Your vehicle mesh]
│   ├── CameraPivot (Node3D)
│   ├── SpawnPoints (Node3D)
│   └── WeaponHardpoints (Node3D)
├── HealthComponent (Node)
├── GunMountPoint (Node3D)
│   └── ProjectileWeapon (extends BaseWeapon)
└── CollisionShape3D
```

### Creating Arena Pickups

```
PickupBase (Area3D)
├── CollisionShape3D (trigger zone)
└── IconContainer (Node3D)
    └── [Rotating visual icon]
```

Place multiple pickups around the arena with different types.

## Input Mapping (Add to Project Settings)

```gdscript
# Add these to project.godot input mappings:
"fire_weapon" - Left Mouse Button
"next_weapon" - Key Q / Scroll Wheel
"prev_weapon" - Key E
```

## Usage Example

### Firing Weapons
```gdscript
# In CombatVehicle or via input
var weapon = vehicle.get_current_weapon()
if weapon and weapon.can_fire():
    weapon.try_fire()
```

### Taking Damage
```gdscript
var health = vehicle.get_node("HealthComponent")
health.take_damage(25.0, "enemy_player_1")
```

### Pickup Collection
```gdscript
# Automatic when vehicle enters Area3D
func _on_PickupBase_pickup_collected(pickup_type: String, position: Vector3):
    print("Collected: ", pickup_type, " at ", position)
```

## Signal Connections for UI

```gdscript
# Health bar
health_component.health_changed.connect(_on_health_changed)

# Hit markers
health_component.hit_registered.connect(_on_hit_registered)

# Kill feed
combat_vehicle.vehicle_destroyed.connect(_on_vehicle_destroyed)

# Boost meter
combat_vehicle.boost_changed.connect(_on_boost_changed)

# Weapon status
weapon.weapon_fired.connect(_on_weapon_fired)
```

## Definition of Done (Sprint 2) ✅

- [x] Vehicle aims turret at camera cursor with smooth rotation
- [x] Projectile weapons fire physical projectiles with large hitboxes
- [x] Hitscan weapons perform instant raycast damage with falloff
- [x] Health component handles damage, death, and respawn
- [x] Vehicles explode (hide/disable) on death and respawn after 4s
- [x] 5 pickup types with unique effects
- [x] Pickups respawn after 10s cooldown
- [x] All signals emitted for UI/VFX integration
- [x] Code structured for Sprint 3 (Networking & Bots)

## Next Steps (Sprint 3)

1. Integrate Colyseus for multiplayer
2. Implement client-side prediction
3. Create bot AI (FSM/Behavior Trees)
4. Sync positions, health, and weapon fire
5. Matchmaking system

## File Structure

```
arena_bowl_game/
├── scripts/
│   ├── components/
│   │   └── health_component.gd          # NEW
│   ├── weapons/
│   │   ├── base_weapon.gd               # NEW
│   │   ├── projectile_weapon.gd         # NEW
│   │   └── hitscan_weapon.gd            # NEW
│   ├── pickups/
│   │   └── pickup_base.gd               # NEW
│   ├── entities/
│   │   └── combat_vehicle.gd            # NEW
│   ├── arcade_vehicle_controller.gd     # UPDATED
│   ├── dynamic_vehicle_camera.gd        # (from Sprint 1)
│   ├── seamless_bowl_arena.gd           # (from Sprint 1)
│   ├── vehicle_scene.gd                 # (from Sprint 1)
│   └── game_manager.gd                  # (from Sprint 1)
└── scenes/
    └── main_game.tscn                   # (from Sprint 1)
```
