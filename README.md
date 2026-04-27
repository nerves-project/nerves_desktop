# Nerves Desktop

A native desktop application for discovering, managing, and provisioning Nerves
devices. Built with **Elixir Phoenix LiveView** and **Tauri** via **ElixirKit**.

## Features

- **Device Discovery**: Automatically find Nerves devices on your local network
  via mDNS.
- **Interactive Console**: Built-in SSH terminal powered by `xterm.js` for
  direct device interaction.
- **Firmware Burner**: Download and flash Nerves firmware images to SD
  cards/storage devices.
- **Nerves Key Management**: Extract information from and provision NervesKey
  hardware security chips (ATECC508A/608A).
- **Allwinner FEL Support**: Interact with Allwinner-based devices (like
  Trellis/Nerves Starter Kit) in FEL mode to flash USB bootloaders.

## Prerequisites

To run this application from source, you need the following installed on your
host machine:

### 1. Development Environment

- **Elixir** (1.15+) and **Erlang/OTP**
- **Rust** and **Cargo** (via [rustup](https://rustup.rs/))
- **Node.js** (for assets)

### 2. System Dependencies (Required for `sunxi` tools)

**macOS**:

```bash
brew install libusb dtc zlib pkg-config
```

**Ubuntu/Debian**:

```bash
sudo apt-get install libusb-1.0-0-dev libfdt-dev zlib1g-dev pkg-config
```

## Getting Started

### 1. Setup Elixir Dependencies

```bash
mix deps.get
```

### 2. Setup Frontend Assets

```bash
npm install --prefix assets
```

### 3. Run the Desktop App

The following command starts the Phoenix server and the native Tauri window
simultaneously:

```bash
cargo tauri dev
```

## Architecture

This project uses **ElixirKit**, which allows a Phoenix LiveView application to
be bundled as a native desktop app using Tauri.

- **Rust (Tauri)**: Handles native windowing, OS integration, and window
  management.
- **Elixir (Phoenix)**: Handles the application logic, background device
  scanning, SSH connections, and the user interface.
- **PubSub Bridge**: Communication between Rust and Elixir is handled via a
  local TCP PubSub bridge provided by ElixirKit.
