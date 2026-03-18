Scope

Core Loop (minimum)
- Move rat
- Lock onto a cat
- Dodge
- Attack
- Cat attacks player
- Player or cat dies

Priority Order
1. Project setup + placeholders
2. Player controller (movement + camera)
3. Dodge roll
4. Attack (simple hitbox)
5. Enemy AI
6. Health/UI + polish

Placeholders
- Rat: capsule
- Cat: cube
- Attack: sphere hitbox
- Arena: plane

Player Structure
- Player
  - CharacterBody3D
  - CollisionShape3D
  - MeshInstance3D (capsule)
  - CameraPivot
    - Camera3D

Dodge (design)
- Input (e.g. space) → burst velocity + invulnerability + cooldown

Attack (design)
- Spawn/enable an Area3D in front of player for ~0.2s to detect hits

Enemy (design)
- Simple loop: detect → move toward player → attack when in range
- Telegraph attacks (windup ~0.6s) using color/scale or pause
