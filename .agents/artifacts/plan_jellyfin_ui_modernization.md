# Plan & Trial Evaluation: Jellyfin Web UI Modernization

## 1. Overview & Objectives
* **Goal**: Modernize the Jellyfin web client with a dark, clean, minimalist interface while preserving 100% compatibility with Jellyfin Enhanced overlays (4K/HDR badges, Seerr actions, Arr tags) and ensuring zero impact on the native Android TV Leanback interface.
* **Jellyfin Server Version**: `12.4.0`
* **Active Plugins**:
  - `Jellyfin Enhanced` (v12.14.0.0)
  - `Media Bar Enhanced` (v3.12.0.0)
  - `File Transformation` (v3.0.3.0)
  - `Local Intros` (v5.0.0.0)

## 2. Active Candidate: Jellyfish (Ocean Palette)
* **Author**: `n00bcodr`
* **Tracked Config**: [`.configs/jellyfin/custom.css`](../../.configs/jellyfin/custom.css)
* **Configuration Modules**:
  - Core Theme: `theme.css`
  - Color Palette: `colors/ocean.css`
  - Slideshow: `slideshow-compact-mobile.css`
  - UI Accents: `indicators.css`, `progress_bar.css`, `bg_scroll.css`
  - Enhanced Integration: `jellyfin-enhanced.css`, `arr-tags-links.css`

## 3. Evaluated Candidates
* **Abyss** (`AumGupta/abyss-jellyfin`): Tested live; rejected due to button text sizing clipping and inconsistent integration with Jellyfin Enhanced badge elements.
* **Finimalism 12** (`tedhinklater/finimalism`): Held as backup minimalist alternative if Jellyfish proves overly complex.

## 4. Evaluation Criteria (24-Hour Trial)
1. Media Bar Enhanced stability and carousel responsiveness on desktop and mobile web.
2. Arr link positioning and tag search accuracy on media detail views.
3. Contrast and legibility of the Ocean dark palette across different display types.
4. Continued normal operation of the native `jellyfin-androidtv` Leanback application.
