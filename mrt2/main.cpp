// Copyright 2026 Google LLC; changes 2026 Émile
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// mrt2: Émile's offline front end to magentart::core, from the repo's
// hello_mrt2. Generates music of a length from a text prompt into a 32-bit
// float stereo WAV at 48 kHz, with a seed, and a tempo held by a drum hit on
// every beat (core.patch's set_drum_token) and pitches outside a scale held
// off (set_pitches_off). Progress and the result are JSON lines on stdout,
// one per line; everything else the engine prints is not JSON.
//
//   mrt2 --model <file.mlxfn> --resources <dir> --seconds <s> --out <file.wav>
//        [--prompt <text>] [--seed <n>] [--bpm <n>] [--scale <pc,pc,…>]
//        [--temperature 1.3] [--top-k 40] [--cfg-musiccoca 3] [--cfg-notes 1]
//        [--cfg-drums 5]

#include <magentart/mlx_engine.h>

#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <thread>
#include <vector>

using namespace magentart::core;

static constexpr int kRate = 48000;  // magentart::core's frames are kFrameSamples (1920) long: 25 a second

static std::string json_escape(const std::string& s) {
    std::string o;
    for (char c : s) {
        if (c == '"' || c == '\\') { o += '\\'; o += c; }
        else if (c == '\n') o += "\\n";
        else if (static_cast<unsigned char>(c) < 0x20) o += ' ';
        else o += c;
    }
    return o;
}

static int fail(const std::string& why) {
    std::fprintf(stderr, "mrt2: %s\n", why.c_str());
    return 1;
}

static bool write_wav(const std::string& path, const std::vector<float>& lr) {
    std::ofstream f(path, std::ios::binary);
    if (!f) return false;
    const uint32_t data = static_cast<uint32_t>(lr.size() * sizeof(float));
    const uint16_t fmt = 3, ch = 2, bits = 32;
    const uint32_t rate = kRate, byte_rate = kRate * ch * bits / 8, size = 36 + data, fmt_size = 16;
    const uint16_t align = ch * bits / 8;
    f.write("RIFF", 4); f.write(reinterpret_cast<const char*>(&size), 4); f.write("WAVE", 4);
    f.write("fmt ", 4); f.write(reinterpret_cast<const char*>(&fmt_size), 4);
    f.write(reinterpret_cast<const char*>(&fmt), 2); f.write(reinterpret_cast<const char*>(&ch), 2);
    f.write(reinterpret_cast<const char*>(&rate), 4); f.write(reinterpret_cast<const char*>(&byte_rate), 4);
    f.write(reinterpret_cast<const char*>(&align), 2); f.write(reinterpret_cast<const char*>(&bits), 2);
    f.write("data", 4); f.write(reinterpret_cast<const char*>(&data), 4);
    f.write(reinterpret_cast<const char*>(lr.data()), data);
    return static_cast<bool>(f);
}

int main(int argc, char** argv) {
    std::string model, resources, out, prompt = "instrumental music", scale;
    double seconds = 0, bpm = 0;
    int seed = 0, top_k = 40;
    float temperature = 1.3f, cfg_musiccoca = 3.0f, cfg_notes = 1.0f, cfg_drums = 5.0f;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (i + 1 >= argc) return fail("missing a value after " + a);
        std::string v = argv[++i];
        if (a == "--model") model = v;
        else if (a == "--resources") resources = v;
        else if (a == "--out") out = v;
        else if (a == "--prompt") prompt = v;
        else if (a == "--scale") scale = v;
        else if (a == "--seconds") seconds = std::atof(v.c_str());
        else if (a == "--bpm") bpm = std::atof(v.c_str());
        else if (a == "--seed") seed = std::atoi(v.c_str());
        else if (a == "--top-k") top_k = std::atoi(v.c_str());
        else if (a == "--temperature") temperature = std::atof(v.c_str());
        else if (a == "--cfg-musiccoca") cfg_musiccoca = std::atof(v.c_str());
        else if (a == "--cfg-notes") cfg_notes = std::atof(v.c_str());
        else if (a == "--cfg-drums") cfg_drums = std::atof(v.c_str());
        else return fail("unknown option " + a);
    }
    if (model.empty() || resources.empty() || out.empty() || seconds <= 0)
        return fail("needs --model, --resources, --seconds and --out");
    if (bpm < 0 || bpm > 300) return fail("--bpm is between 0 and 300");

    const auto t0 = std::chrono::steady_clock::now();
    MLXEngine engine;
    if (!engine.init_assets(resources.c_str(), "musiccoca")) return fail("could not load the style model from " + resources);
    if (!engine.load_model(model.c_str())) return fail("could not load the model " + model);
    engine.set_temperature(temperature);
    engine.set_top_k(top_k);
    engine.set_cfg_musiccoca(cfg_musiccoca);
    engine.set_cfg_notes(cfg_notes);
    engine.set_cfg_drums(bpm > 0 ? cfg_drums : 1.0f);
    engine.set_seed_rotation(seed);
    engine.reset_state();
    engine.set_text_prompt(prompt);
    if (!scale.empty()) {
        bool in[12] = {};
        size_t s = 0;
        while (s < scale.size()) {
            size_t e = scale.find(',', s);
            if (e == std::string::npos) e = scale.size();
            int pc = std::atoi(scale.substr(s, e - s).c_str());
            if (pc < 0 || pc > 11) return fail("--scale is pitch classes 0–11, comma separated");
            in[pc] = true;
            s = e + 1;
        }
        bool off[128];
        for (int k = 0; k < 128; ++k) off[k] = !in[k % 12];
        engine.set_pitches_off(off);
    }
    // The text encoder runs on a thread: 1 in flight, 2 done, 3 failed
    while (engine.get_text_encoder_status() == 1 || engine.get_quantizer_status() == 1)
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    if (engine.get_text_encoder_status() == 3 || engine.get_quantizer_status() == 3)
        return fail("could not read the prompt");

    const int frames = static_cast<int>(std::lround(seconds * 25));
    const double step = bpm > 0 ? 25.0 * 60.0 / bpm : 0;
    std::vector<float> lr;
    lr.reserve(static_cast<size_t>(frames) * kFrameSamples * 2);
    std::vector<float> L(kFrameSamples), R(kFrameSamples);
    for (int f = 0; f < frames; ++f) {
        if (step > 0) {
            long k = std::lround(f / step);
            engine.set_drum_token(std::lround(k * step) == f ? 1 : 0);
        }
        if (!engine.generate_frame(L.data(), R.data())) return fail("generation stopped at frame " + std::to_string(f));
        for (size_t i = 0; i < kFrameSamples; ++i) { lr.push_back(L[i]); lr.push_back(R[i]); }
        if ((f + 1) % 25 == 0 || f + 1 == frames)
            std::printf("{\"type\":\"progress\",\"progress\":{\"done\":%d,\"total\":%d}}\n", f + 1, frames), std::fflush(stdout);
    }
    if (!write_wav(out, lr)) return fail("could not write " + out);
    const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    std::printf("{\"type\":\"result\",\"value\":{\"out\":\"%s\",\"seconds\":%.3f,\"frames\":%d,\"ms\":%.0f}}\n",
                json_escape(out).c_str(), static_cast<double>(lr.size() / 2) / kRate, frames, ms);
    return 0;
}
