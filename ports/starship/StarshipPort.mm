// Starship's side of the engine glue. See engine/HarbourPort.h.

#include "HarbourPort.h"

#include <SDL2/SDL.h>
#include <yaml-cpp/yaml.h>

#include <filesystem>
#include <fstream>
#include <iterator>
#include <memory>
#include <optional>
#include <string>
#include <system_error>
#include <unordered_map>
#include <utility>
#include <vector>

#include "Companion.h"
#include "Context.h"
#include "window/Window.h"
#include "window/gui/Gui.h"

// VER_FILEVERSION_STR, configured from the CMake project's version.
#include "properties.h"

// src/port/extractor/GameExtractor.cpp: the ROMs the game can extract, by the SHA-1 of the .z64.
extern std::unordered_map<std::string, std::string> mGameList;

namespace {

namespace fs = std::filesystem;

bool ReadRom(const char* path, std::vector<uint8_t>* rom) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        return false;
    }
    *rom = std::vector<uint8_t>(std::istreambuf_iterator<char>(file), {});
    return !rom->empty();
}

// The archive Torch writes for the ROM with `hash`, relative to the data directory, as config.yml names it. A
// compressed dump's entry only names the decompressed ROM, whose entry names the archive.
std::optional<fs::path> ArchiveForRom(const fs::path& specs, const std::string& hash) {
    try {
        // Const, so looking up a missing key doesn't add it.
        const YAML::Node config = YAML::LoadFile((specs / "config.yml").string());
        std::string key = hash;
        if (const YAML::Node preprocess = config[hash]["preprocess"]) {
            for (const auto& job : preprocess) {
                if (const YAML::Node target = job.second["target"]) {
                    key = target.as<std::string>();
                }
            }
        }
        const YAML::Node binary = config[key]["config"]["output"]["binary"];
        if (!binary) {
            return std::nullopt;
        }
        return fs::path(binary.as<std::string>()).lexically_normal();
    } catch (const std::exception& e) {
        SDL_Log("Starship: can't read the extraction specs: %s", e.what());
        return std::nullopt;
    }
}

} // namespace

namespace HarbourPort {

const char* GameVersion() {
    return VER_FILEVERSION_STR;
}

bool IdentifyRom(const char* path, std::string* /*description*/) {
    std::vector<uint8_t> rom;
    if (!ReadRom(path, &rom)) {
        return false;
    }
    return mGameList.find(Companion::CalculateHash(rom)) != mGameList.end();
}

bool ExtractRom(const char* path, std::atomic<size_t>* done, std::atomic<size_t>* total) {
    // What GameEngine::GenAssetFile does with GameExtractor, minus its message boxes and file dialog. Torch has no
    // progress reporting, so progress stays indeterminate.
    std::vector<uint8_t> rom;
    if (!ReadRom(path, &rom)) {
        return false;
    }
    const std::string hash = Companion::CalculateHash(rom);
    if (!mGameList.contains(hash)) {
        return false;
    }

    const std::string source = Ship::Context::GetAppBundlePath();
    const std::string destination = Ship::Context::GetAppDirectoryPath();
    const std::optional<fs::path> archive = ArchiveForRom(source, hash);
    if (!archive.has_value()) {
        return false;
    }
    const fs::path output = fs::path(destination) / *archive;

    std::error_code error;
    // Torch writes voice packs into mods/, and its zip writer fails silently when the folder is missing.
    fs::create_directories(output.parent_path(), error);
    // Torch skips every spec whose hash torch.hash.yml lists as exported already, so a second extraction of the
    // same ROM would write an empty archive.
    const fs::path hashes = fs::path(destination) / "torch.hash.yml";
    fs::remove(hashes, error);
    const std::optional<fs::file_time_type> previousTime =
        fs::exists(output, error) ? std::optional(fs::last_write_time(output, error)) : std::nullopt;

    // Strings, not char pointers, for the directories: with those, overload resolution picks the constructor whose
    // fourth parameter is the bool `modding`.
    auto companion = std::make_unique<Companion>(std::move(rom), ArchiveType::O2R, false, source, destination);
    Companion::Instance = companion.get();
    bool finished = true;
    try {
        companion->Init(ExportType::Binary);
    } catch (const std::exception& e) {
        SDL_Log("Starship: extraction failed: %s", e.what());
        finished = false;
    } catch (...) {
        SDL_Log("Starship: extraction failed");
        finished = false;
    }
    // Torch resets these itself only when it gets to the end.
    Companion::Instance = nullptr;
    Decompressor::ClearCache();
    companion.reset();
    fs::remove(hashes, error);

    // Torch returns without an error on several failures (no spec for the ROM, an invalid one), so check that it
    // wrote the archive.
    const uintmax_t size = fs::file_size(output, error);
    if (!finished || error || size == 0) {
        return false;
    }
    return !previousTime.has_value() || fs::last_write_time(output, error) != *previousTime;
}

bool IsArchiveOutdated(const char* path) {
    // Starship doesn't check its archives' versions.
    return false;
}

int MenuScancode() {
    // Starship has a menu bar only, which F1 toggles; Escape opens nothing.
    return SDL_SCANCODE_F1;
}

bool IsMenuOpen() {
    std::shared_ptr<Ship::Context> context = Ship::Context::GetInstance();
    std::shared_ptr<Ship::Window> window = context != nullptr ? context->GetWindow() : nullptr;
    std::shared_ptr<Ship::Gui> gui = window != nullptr ? window->GetGui() : nullptr;
    return gui != nullptr && gui->GetMenuOrMenubarVisible();
}

} // namespace HarbourPort
