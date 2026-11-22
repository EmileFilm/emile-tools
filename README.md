# emile-tools

The programs Émile downloads that we build ourselves, with how to build them
again. Émile's engine lists each release file with its SHA-256
(`engine/lib/tools.mjs`) and fetches it on first use, as it does ffmpeg.

| Folder | Program | What it is | Upstream | Licence |
|---|---|---|---|---|
| `ffmpeg/` | `ffmpeg`, `ffprobe` | Reads, filters and encodes every video and sound Émile makes; built without any GPL part, H.264, HEVC and AAC by the system's encoders | [FFmpeg](https://ffmpeg.org) 9.0.2, unchanged (with dav1d, libvpx, opus, freetype, harfbuzz) | LGPL-2.1-or-later |
| `mrt2/` | `mrt2` | Generates music from a text prompt, offline, on Apple Silicon | [magenta/magenta-realtime](https://github.com/magenta/magenta-realtime) (pinned commit in `build.sh`) | Apache-2.0 |
| `sfizz/` | `sfizz_render` | Plays a MIDI file through an SFZ instrument into a 32-bit float WAV | [sfztools/sfizz](https://github.com/sfztools/sfizz) (pinned commit in `build.sh`) | BSD-2-Clause |

## ffmpeg

FFmpeg's release, unchanged, with no `--enable-gpl` and no `--enable-nonfree`:
no x264 or x265. Linked in statically: dav1d (reads AV1), libvpx (writes VP9),
opus, freetype and harfbuzz (words on a contact sheet). Every other library is
macOS's own. `ffmpeg/VERSION` is FFmpeg's version and our build of it; the
build checks that `CONFIG_GPL` is 0 and that nothing but the system's libraries
is linked dynamically.

## mrt2

Magenta RealTime 2's C++ engine (`magentart::core`) with two additions in
`mrt2/core.patch` (about 40 lines): a drum token set per frame
(`set_drum_token`: a hit on every beat holds a tempo) and pitches held off
(`set_pitches_off`: leans toward a scale). `mrt2/main.cpp` is the front end
Émile runs: seconds, prompt, seed, tempo and scale in; a 48 kHz float WAV out,
progress as JSON lines. The model weights are not here: Émile downloads
`google/magenta-realtime-2` (CC-BY-4.0) from Hugging Face.

    mrt2 --model <file.mlxfn> --resources <dir> --seconds <s> --out <file.wav>
         [--prompt <text>] [--seed <n>] [--bpm <n>] [--scale <pc,pc,…>]

## sfizz_render

sfizz with one change, `sfizz/render.patch`: it writes 32-bit float in place
of 16-bit, so a quiet part keeps its detail when Émile brings the mix to
loudness. The build also turns off a check newer clang added that sfizz's
bundled `atomic_queue` fails.

## Building

    pip install meson ninja pkgconf cmake             # ffmpeg (cmake any version)
    pip install "cmake<3.28"                          # Magenta's build needs it
    xcodebuild -downloadComponent MetalToolchain      # MLX's kernels
    ffmpeg/build.sh arm64 && ffmpeg/build.sh x64      # x64 is cross-built
    mrt2/build.sh
    sfizz/build.sh

Each writes `dist/<name>-<version>-macos-<arm64|x64>.zip` (the program, every
licence under `LICENSES/`) and prints its SHA-256. A release is tagged
`<name>-<version>` with that file attached.

The build scripts and `main.cpp` are Apache-2.0 (`LICENSE`); each program
keeps its own licence.
