# Lua Voxel

Lua Voxel is a high-performance voxel engine written in LuaJIT using LÖVE2D and OpenGL GLSL. The engine renders the world entirely on the GPU using ray tracing instead of traditional mesh generation, allowing for dynamic lighting, reflections, and physically based materials while keeping the CPU focused on world simulation and streaming.

## Features

- GPU ray-traced voxel renderer
- Physically based materials (PBR)
- Real-time reflections
- Ambient occlusion
- Dynamic sky and sun lighting
- Atmospheric fog
- HDR rendering with ACES tonemapping
- Infinite procedural terrain
- Asynchronous chunk streaming
- Multi-threaded world generation
- GPU 3D voxel textures
- Brick acceleration structure for faster ray traversal
- FFI-accelerated voxel editing
- Persistent chunk loading and saving

## Built With

- LuaJIT
- LÖVE2D
- OpenGL GLSL
- Lua FFI

## Goals

The goal of this project is to explore how far LÖVE2D can be pushed for modern voxel rendering. The engine focuses on rendering large procedural worlds with high visual quality while maintaining good performance through GPU-based rendering, multithreading, and efficient data structures.

This project is still under active development, and both performance and rendering quality are continually being improved.
