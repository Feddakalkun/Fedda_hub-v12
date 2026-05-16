# FEDDA Hub v12 (Reset Baseline)

This is a clean restart baseline with two priorities:

1. Installer must work reliably.
2. Basic UI shell must run reliably.

## Quick Start

From the repo root:

- `FEDDA_OneClick_Installer-v12.bat` (first-time setup)
- `FEDDA_run-v12.bat` (run dev UI)
- `FEDDA_Update-v12.bat` (pull latest + reinstall deps)

## Structure

- `frontend/` - minimal React + Vite UI shell
- root `.bat` files - setup/run/update wrappers
