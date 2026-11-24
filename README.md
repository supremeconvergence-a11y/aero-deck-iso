# Nuvio Aero OS ISO builder

Builds the **Nuvio Aero OS** (Aero Deck) live ISO on GitHub Actions, for free.

The finished ISO is a single `.iso` file. Burn it with **Rufus (DD Image mode)** or balenaEtcher and boot the Deck.

- Source tarball: `Nuvio Aero OS.tar.gz` (see the `.sha256` file)
- Workflow: `.github/workflows/build.yml` (runs on push and via *Run workflow*)
- The ISO is uploaded to a public Gofile download page (the main link). Split files may also be attached to a GitHub Release as a backup.

This repository does not contain IPTV passwords, keystore passwords, or the Secure Boot private key. The workflow generates a one-time Secure Boot signing key on the runner, puts only the public certificate in the ISO, and deletes the private key before any upload. The first boot of a new USB shows a one-time MOK enrollment screen (see the README inside the tarball).
