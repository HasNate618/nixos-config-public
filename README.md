# NixOS Homelab Configuration

Declarative, version-controlled infrastructure for a two-machine NixOS setup: a homelab server and a Hyprland desktop, managed from a single flake.

## What this is

A real self-hosted platform with around 40 services across two machines, the homelab server (Intel i5-6600K, NVIDIA GTX 960) and the desktop (Intel i9-13900H, NVIDIA RTX 4060). Everything is configured declaratively with Nix. A bad change means booting the previous generation, not hours of manual recovery.

The desktop side is the interesting one from a systems standpoint. It is an ASUS ROG Flow X16 laptop with the GPU locked to 55W by firmware, an Intel iGPU, a mini-LED panel, and a Corne split keyboard. Getting all of that to behave under Linux took real debugging, and most of it lives in `hosts/nixos/default.nix` plus the `modules/nixos/` tree.

On top of the hardware work sits a fairly deep desktop theme stack. A wallpaper daemon derives Material You palettes from the current image and pushes them through templates to every app, live, with no rebuild. A focus mode dims everything but the active window and swaps in one of thirteen colour schemes on demand.

## Why NixOS

The previous setup was Debian with Docker Compose. Config drift crept in as packages accumulated and manual patches stacked up, and neither machine could be reproduced from scratch. NixOS solved that. Every package, service, and setting is declared in version-controlled Nix files. Atomic upgrades, rollbacks, and one source of truth for two machines.

## Architecture

### System architecture

```mermaid
flowchart TB
    subgraph clients["Clients"]
        flow["Desktop (flow)<br/>i9-13900H · RTX 4060 · Hyprland"]
        remote["Remote devices<br/>Tailscale mesh"]
        lan["Home LAN<br/>limited access"]
    end

    subgraph home["Homelab (home) · i5-6600K · GTX 960 · Docker"]
        caddy["Caddy reverse proxy"]
        infra["Core infra<br/>PostgreSQL · Redis · AdGuard · CrowdSec"]
        access["Access<br/>Forgejo · Nextcloud · Vaultwarden · FileBrowser"]
        media["Media<br/>Jellyfin · Immich · *arr stack"]
        ai["AI platform<br/>Open WebUI · Bifrost · Trawl · EmbeddingGemma"]
        mon["Monitoring<br/>Glance · Uptime Kuma · Netdata · ntfy"]
    end

    nas["Synology NAS<br/>media · photos · backups"]

    remote -->|"encrypted VPN, no public ports"| caddy
    flow --> home
    lan -->|"DNS-filtered"| caddy
    caddy --> access & media & ai & mon
    infra --> access & media & ai & mon
    home --> nas
```

### Configuration structure

Two NixOS hosts (`flow`, `home`) and one home-manager profile, all driven from a single flake:

```mermaid
flowchart LR
    subgraph repo["Git repo"]
        flake["flake.nix<br/>inputs · nixosConfigurations"]
        hosts["hosts/<br/>flow/ · home/ · live-usb/"]
        mods["modules/<br/>nixos/ · server/ · shared/"]
        hm["home/nate/<br/>desktop dotfiles & tooling"]
        secrets["secrets/<br/>SOPS-encrypted age keys"]
    end

    subgraph deploy["Deploy"]
        rebuild["nixos-rebuild switch<br/>atomic · rollback-safe"]
    end

    flow["flow - desktop<br/>Hyprland · NVIDIA · llama.cpp"]
    homehost["home - homelab<br/>~40 Docker services"]

    flake --> hosts & mods & hm & secrets
    repo --> rebuild
    rebuild --> flow & homehost
    mods --> flow & homehost
    hm --> flow
```

### Services

Infrastructure: PostgreSQL 16, Redis, AdGuard Home, CrowdSec, Docker, Gluetun. Core platform services, databases, DNS filtering, intrusion detection, and VPN isolation for egress.

Access: Caddy, Forgejo, Nextcloud, Collabora, Vaultwarden, FileBrowser. Reverse proxy, self-hosted Git, cloud storage, a password manager, and a web file manager over the NAS shares.

AI: Bifrost, Open WebUI, crawl4ai, SearXNG, DeGoog, Trawl, Excalidraw, Whisper, Open Terminal, Brightspace MCP, Campus, EmbeddingGemma. LLM gateway, web UI for models, web scraping, search, document tooling, an MCP server for the Brightspace LMS, a personal study-sync agent harness, and a local multimodal embedding server.

Media: Jellyfin, the *arr stack (Sonarr, Radarr, Lidarr, Prowlarr), Immich. Media streaming, automated media management, and a photo library.

Monitoring: Glance, Uptime Kuma, Netdata, ntfy. Dashboards, uptime monitoring, system metrics, and push notifications.

PDF pipeline: pdf-extractor, pdf-ocr, pdf-parse, bentopdf. Document parsing, local OCR, and a Cohere-Parse-compatible service built from repo source.

Games: Lunar Tear, a private server for a discontinued mobile game. Three containers pinned by digest, with ports published only on the Tailscale address.

### Security

```mermaid
flowchart TB
    internet["Internet"]

    subgraph clients["Clients"]
        lan["LAN devices<br/>router DNS → dnsmasq"]
        remote["Tailscale devices<br/>tailnet DNS override"]
        docker["Docker containers<br/>host loopback resolver"]
    end

    subgraph dnscontrol["DNS control plane · AdGuard Home"]
        adguard["AdGuard Home<br/>network-wide resolver"]
        filter["Filtering · DNSSEC · DoH upstream"]
        rewrite["*.home.lab rewrites<br/>remote → tailnet IP"]
        dnsmasq["dnsmasq split-horizon<br/>LAN *.home.lab → Caddy LAN IP"]
        querylog["Query logging · statistics"]
    end

    subgraph zerotrust["Zero-trust access"]
        ts["Tailscale mesh<br/>no port forwarding"]
    end

    subgraph perimeter["Perimeter defense"]
        caddy["Caddy reverse proxy<br/>Jellyfin-only on LAN IP"]
        cs["CrowdSec IDS<br/>Caddy logs → IP bans"]
    end

    subgraph isolation["Service isolation"]
        glu["Gluetun VPN container<br/>qBittorrent · scrapers only"]
        dnet["Docker networks<br/>scoped connectivity"]
    end

    subgraph secretsmgmt["Secrets at rest"]
        sops["sops-nix<br/>age-encrypted · decrypted at boot"]
    end

    internet -.->|"direct HTTP blocked"| caddy
    lan --> dnsmasq --> adguard
    remote --> ts --> adguard
    docker --> adguard
    adguard --> filter & rewrite & querylog
    rewrite --> caddy
    dnsmasq --> caddy
    caddy --> cs
    caddy --> dnet
    dnet --> glu
    sops --> dnet
```

AdGuard Home is the security control plane, not just an ad blocker. Every LAN, Tailscale, and Docker client resolves through it. It filters malicious and tracker domains, validates DNSSEC, and sends upstream queries over DoH. DNS rewrites for `*.home.lab` replace Authelia SSO: remote clients only reach services when Tailscale is connected and AdGuard returns the tailnet IP. On the LAN, dnsmasq provides split-horizon answers so `*.home.lab` resolves to Caddy's LAN address while everything else still flows through AdGuard for filtering. CrowdSec handles HTTP-layer intrusion prevention; Gluetun isolates torrent and scraper egress.

## Desktop environment

The `flow` host runs Hyprland with a Quickshell status bar written from scratch. Both are wired into a theming pipeline that reacts to the wallpaper rather than to a static palette.

Wallpaper to palette. `skwd-wall` watches the wallpaper, runs matugen to extract a Material You scheme, and renders it through 31 templates (foot, kitty, ghostty, btop, cava, GTK3/4, Kvantum, qt6ct, swayosd, yazi, lazygit, neovim, Hyprland borders, hyprlock, Zen, Vesktop, wl-kbptr). One wallpaper change repaints the desktop live. The daemon is a NixOS unit, and the templates deploy through home-manager.

Focus mode. `SUPER+SHIFT+ESCAPE` toggles a mode that repaints every surface to a flat scheme colour, gates the Quickshell animations, and hides the non-essential chrome. Thirteen schemes ship in-tree (Dracula, Gruvbox, Kanagawa, Nord-ish, Tokyo Night, and so on) and switch live with `focus-scheme <name>`; the active choice is a runtime file, not a rebuild. The theming scripts self-resolve the Hyprland signature and repaint app themes in place, recycling the terminal multiplexer client rather than restarting it.

Quickshell bar. Desktop and laptop clusters, omni menu (clipboard plus emoji search), battery and volume OSDs, notification OSD, brightness, weather, calendar, and a workspace pager. Every widget carries its own accent hue derived from the active scheme, and the bar is gated so it goes inert in focus mode.

Zen Browser. Patched with an autoconfig wrapper that polls the live theme CSS, so the browser chrome tracks the wallpaper like every other surface. Extensions install declaratively from vendored `.xpi` files.

## Custom tools

Trawl. A web scraping and search API built on crawl4ai and SearXNG. It returns clean markdown from any URL, runs web search across multiple backends, and discovers links. It powers the agent's ability to read and process web content.

skwd-wall. The wallpaper daemon described above: matugen scheme extraction plus template rendering, exposed as `skwd-wall` (picker), `skwd-helm` (CLI), and `skwd-walld` (daemon). Config is app-owned and diffed against the declarative source, so drift is visible rather than silent.

## Notable challenges

GPU power cap. The RTX 4060 was locked to 55W by ASUS firmware, well below its rated wattage. NVIDIA's own `nvidia-powerd` was blocked by the SBIOS unless the thermal policy was set to Performance before it initialized. The fix was a chain of boot services that write the ASUS EC power values (dynamic boost budget, CPU package limits) before `nvidia-powerd` starts, plus tuning the RAPL MMIO power domain directly and declaring the values in `asusd.ron`. The GPU now holds around 87W under load.

Platform profile switching. A 15-second timer watches the ACPI platform profile and switches the display between 60Hz on battery and 240Hz on AC, syncs TLP power source, and corrects CPU limits that leak in when the quiet profile flips. It is change-gated so an unchanged tick exits in about a millisecond instead of running a full pipeline every loop, which mattered because the old unconditional poll kept the CPU out of deep sleep states.

Mini-LED lifecycle. The panel's multi-zone backlight is enabled before shutdown for deep blacks on dark screens, and restored to single-zone on boot for text clarity. Two systemd oneshot services toggle it around the suspend and resume cycle. Get the ordering wrong and you either lose the local dimming entirely or boot into a panel that renders subpixel text badly.

Focus mode animation gating. The first focus-mode implementation only gated the animations that were easy to find, and the ones that were missed kept the compositor busy repainting surfaces that were supposed to be static. Tracking down the remainder meant auditing every animation binding in the Quickshell tree, including ones hidden behind lazy-loaded panes, and making the accessor root declare the focus flag so a bad binding fails loudly instead of silently no-oping.

## Hardware

Homelab: server, Intel i5-6600K, NVIDIA GTX 960 (2GB), 16GB RAM, 225GB NVMe, NixOS 26.05.

Flow: desktop, Intel i9-13900H, NVIDIA RTX 4060 (8GB), 32GB RAM, 1TB NVMe, NixOS 26.05.

## Getting started

This is a personal infrastructure configuration, not a turnkey project. It is documented for reference and learning. Adapting it to your own hardware and services requires understanding NixOS modules and flakes.

1. Clone the repository.
2. Review `hosts/<name>/default.nix` for host-specific configuration.
3. Generate your hardware configuration with `nixos-generate-config --show-hardware-config`.
4. Adjust `modules/server/` for your service requirements.
5. Set up sops-nix for secret management.
6. Rebuild with `sudo nixos-rebuild switch --flake .#<hostname>`.

Some assets are deliberately not committed: the SOPS-encrypted secrets, the private CA certificate, browser extension binaries, and wallpaper images. The Nix modules reference them by path, so the `home` host will not finish evaluating without your own `secrets/homelab.yaml`. Supply your own or comment those lines out.

## Tech stack

Platform: NixOS, Nix flakes, Docker, systemd.
Networking: Tailscale (mesh VPN), Caddy (reverse proxy), AdGuard Home (DNS), CrowdSec (IDS).
Databases: PostgreSQL 16, Redis.
AI and ML: Bifrost (LLM gateway), Open WebUI, crawl4ai, SearXNG, Playwright, EmbeddingGemma.
Media: Jellyfin, Immich, Sonarr, Radarr, Lidarr, Prowlarr.
Monitoring: Glance, Uptime Kuma, Netdata, ntfy.
Desktop: Hyprland, Quickshell (QML), matugen, skwd-wall, Zen Browser.
Secrets: sops-nix (age encryption).
Languages: Nix, Python, Bash, QML.

## License

MIT
