# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Project Apollo - NASSP is a study-grade simulation add-on for the Orbiter space flight simulator. It simulates Apollo missions with near-complete control panel implementations for the Command Module (CM) and Lunar Module (LM), accurate internal systems simulation (electrical, fuel cells, environmental control), and integration with Virtual AGC to run authentic Apollo Guidance Computer software.

## Build Requirements

- **Orbiter 2024 x64** installed
- **Visual Studio 2019 or 2022** (2022 preferred)
- NASSP must be checked out inside the Orbiter installation directory

## Building

Open `Orbitersdk/samples/ProjectApollo/ProjectApollo2017.sln` in Visual Studio and build. The solution contains 45+ projects for various spacecraft modules and ground support equipment.

Key projects:
- **Saturn5NASP** / **Saturn1b**: Main Saturn V and Saturn IB launch vehicles
- **LEM**: Lunar Module
- **PanelSDK**: Shared library for electrical/hydraulic/thermal simulation
- **ApolloRTCCMFD**: Real-Time Computer Complex MFD for mission planning
- **MCC**: Mission Control Center simulation

Build outputs DLLs directly into the Orbiter `Modules` directory structure.

## Code Architecture

### Source Organization (`Orbitersdk/samples/ProjectApollo/`)

- **src_csm/**: Command/Service Module - `saturn.cpp/.h` is the main vessel class with panel, systems, and mesh code
- **src_lm/**: Lunar Module - `LEM.cpp/.h` is the main class; subsystems in `lm_*.cpp` files (ecs, eps, rcs, dps, aps, etc.)
- **src_saturn/**: Saturn launch vehicle stages and systems - includes S-IC (`s1c`), S-II (`sii`), S-IVB (`sivb`), IU (Instrument Unit), LVDC (Launch Vehicle Digital Computer)
- **src_sys/**: Shared systems code - AGC interface (`apolloguidance.cpp`), DSKY, IMU, switches (`toggleswitch.cpp`), sound, connectors
- **src_rtccmfd/**: Real-Time Computer Complex MFD - orbital mechanics, targeting, mission planning
- **src_launch/**: Ground support - launch pads (LC34, LC37), VAB, crawler, MCC, RTCC

### Key Subsystem Patterns

Each spacecraft subsystem typically follows this pattern:
- Separate `.cpp/.h` files per subsystem (e.g., `scs.cpp` for Stabilization & Control, `secs.cpp` for Sequential Events Control)
- Subsystems connect via the **Connector** pattern (`connector.cpp/.h`, `csmconnector.cpp`, `lemconnector.cpp`)
- Panel switches defined in `satswitches.cpp` (CSM) and `lemswitches.cpp` (LM)
- Virtual cockpit rendering in `*vc.cpp` files

### PanelSDK Framework (`src_sys/PanelSDK/`)

Core simulation framework providing:
- **Esystems**: Electrical system simulation (power sources, buses, loads)
- **Hsystems**: Hydraulic/fluid system simulation (tanks, pipes, valves, pumps)
- **Thermal**: Thermal simulation engine

Systems are defined in configuration files and parsed at runtime.

### Virtual AGC Integration (`src_sys/yaAGC/`)

Contains the yaAGC (Yet Another AGC) emulator that runs authentic Apollo Guidance Computer flight software. The `agc_engine.c` provides cycle-accurate CPU emulation.

## Coding Conventions

- Use **TABS** for indentation
- Use **LF** line endings
- Each subsystem should be in its own file
- Follow existing naming patterns (e.g., CSM systems prefixed appropriately, LM systems use `lm_` prefix)

## Key Classes

- **Saturn**: Base class for Saturn vehicles (`saturn.h`) - extremely large class handling all CSM functionality
- **LEM**: Lunar Module vessel class (`LEM.h`)
- **ApolloGuidance**: AGC interface base class; specialized as **CSMcomputer** and **LEMcomputer**
- **RTCC**: Real-Time Computer Complex for mission control calculations
- **IU**: Instrument Unit containing LVDC for launch vehicle guidance

## Configuration Files

- `Config/`: Vessel and mission configuration
- `Scenarios/`: Orbiter scenario files for different mission phases
- `Meshes/`: 3D mesh files
- `Textures/`: Texture files for spacecraft and panels
