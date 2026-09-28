# Local Translator — approved logo, DESIGN02

Two interlocking speech panels represent source and translation. Wave bars identify meeting audio; horizontal strokes identify text/subtitles. No change to the feature implementation order.

## Deliverables

- `local-translator-logo.png`: approved DESIGN01 color master, 1254 × 1254 RGBA, transparent background, unchanged.
- `menu-bar-master.png`: monochrome adaptation, center-cropped to 960 × 960 for small-size occupancy. Wave/subtitle strokes and panel separation are transparent cutouts.
- `LocalTranslator.icns`: standalone macOS icon package.
- `icon-preview.png`: AppKit render on light/dark backgrounds, including 18 pt template samples; a preview, not a screenshot of the running menu bar.
- Installed app assets: `../../LocalTranslator/Assets.xcassets/AppIcon.appiconset` (16/32/128/256/512 pt at 1×/2×).
- Installed menu asset: `../../LocalTranslator/Assets.xcassets/MenuBarIcon.imageset` (18/36 px, template rendering intent).

## Generation and export

Built-in ImageGen produced the approved color design and the monochrome adaptation. No new dependency or runtime image generation. PNG resizing/cropping used macOS `sips`; ICNS packaging used `iconutil`. Master images remain available here independently of the generator cache. The only Swift integration change is MenuBarExtra's named `MenuBarIcon` asset in place of `character.bubble`.

Color master prompt (DESIGN01):

> Use case: logo-brand. Design one polished original macOS application logo for Local Translator, a private fully local utility with two equal features: selected-text translation and live meeting audio translated into paired original-language and translated subtitles. Create a single premium, minimal, vector-like app icon, centered on a plain light neutral background, square composition. The mark: two overlapping rounded caption/speech panels forming a compact connected emblem, one panel contains a very simple short audio waveform of three bold rounded vertical strokes, the other contains two bold horizontal subtitle strokes. Make the panels and their negative space feel like one cohesive distinctive glyph, not separate clipart. Strong silhouette legible at small size, generous spacing, consistent bold rounded geometry, restrained dimensional depth and immaculate edges. Tasteful cool colors with excellent contrast, contemporary native macOS aesthetic. No letters, no words, no mockup devices, no explanatory labels, no grids of variants, no microphone, no robot, no brain, no cloud, no globe, no sparkle. Deliver only one finished icon filling roughly 75 percent of the square canvas; calm uncluttered and recognizable. This is a logo design preview, not a screenshot of the app.

Monochrome adaptation prompt (DESIGN02; approved color master supplied as reference):

> Create a production monochrome macOS menu bar TEMPLATE ICON derived faithfully from the supplied approved Local Translator logo. Keep its recognizable two interlocking offset chat bubbles: upper-left bubble containing three short rounded vertical audio-wave bars; lower-right bubble containing two short horizontal subtitle bars. Simplify for excellent legibility at 18 points. Pure solid BLACK silhouette and TRANSPARENT cutouts for the wave bars and subtitle bars. Add a clear transparent separation between overlapping bubbles so they remain distinguishable in one color. Genuine transparent background, no white backdrop. Flat vector-like perfectly clean smooth edges, no gradients, no glow, no shadows, no color, no fine details. Center emblem with about 10 percent clear margin each side, balanced square canvas. The result must be a single symbol, no text, no labels, no mockup or icon tile. Deliver a high resolution transparent PNG suitable for standard downsampling to macOS @1x/@2x menu bar assets.

## Limits

These are raster assets, not editable vector masters. Small-size template rendering was checked using AppKit; actual menu bar/Finder appearance and OS icon caching still need a check after relaunching the rebuilt app. Do not clear system icon caches or replace a running app automatically.
