Ganossa Motion Focus - Modernized Edition with Motion Fisheye
=================

 Ganossa Motion Focus port with Motion Fisheye support 
 Original concept: Ganossa (mediehawk@gmail.com) 
 Original port credit: IDDQD 
 
Modernization goals:
- Keep the original motion-following idea.
- Remove the resolution-dependent 5184 normalization.
- Replace the legacy ~192x108 analysis loop with a fixed 32x18 grid.
- Make motion detection usable with HDR / wide luminance ranges.
- Add temporal persistence and focus smoothing controls.
- Add independent Fisheye deadzone and frame-rate-independent persistence.
- Use a centered zoom transform instead of the legacy edge-correction formula.
- Avoid discard-based partial rendering.
 
 Target:
 ReShade 6.x / current ReShade FX
------------

ReShade FX shaders
==================

This repository aims to collect post-processing shaders written in the ReShade FX shader language.

Installation
------------

1. [Download](https://github.com/crosire/reshade-shaders/archive/master.zip) this repository
2. Extract the downloaded archive file somewhere
3. Start your game, open the ReShade in-game menu and switch to the "Settings" tab
4. Add the path to the extracted [Shaders](/Shaders) folder to "Effect Search Paths"
5. Add the path to the extracted [Textures](/Textures) folder to "Texture Search Paths"
6. Switch back to the "Home" tab and click on "Reload" to load the shaders

Contributing
------------

Check out [the language reference document](REFERENCE.md) to get started on how to write your own!
