# secret-mines-cinematic

A WebGL shader visualization project that renders real-time graphics using GLSL shaders.

## Project Overview

This project creates an interactive WebGL canvas that runs fragment shaders for cinematic visual effects. It includes:

- **WebGL Renderer**: A minimal WebGL setup for fullscreen shader rendering
- **Shader Loader**: Dynamic loading and compilation of GLSL shaders
- **Interactive Controls**: Mouse position tracking and time-based animations
- **Responsive Design**: Automatic canvas resizing to fit the window

## Project Structure

```
src/
├── index.html      # Main HTML page with WebGL canvas
├── main.js         # WebGL setup and shader compilation logic
└── shader.glsl     # Fragment shader with time-based animations
```

## How to Run

To preview the shader visualization locally:

1. Navigate to the `src` directory:
   ```bash
   cd src
   ```

2. Start a local HTTP server:
   ```bash
   python -m http.server 8000
   ```

3. Open your browser and navigate to:
   ```
   http://localhost:8000
   ```

## Features

- Real-time shader rendering with WebGL
- Mouse interaction support
- Time-based animations via `iTime` uniform
- Fullscreen canvas with automatic resizing
- Compatible with modern browsers supporting WebGL