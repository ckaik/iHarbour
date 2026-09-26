// SpaghettiKart's side of the engine glue. See engine/HarbourPort.h.

#include "HarbourPort.h"

#include <SDL2/SDL.h>
#include <ship/Context.h>
#include <ship/window/Window.h>
#include <ship/window/gui/Gui.h>
#include <zip.h>

#include <filesystem>
#include <fstream>
#include <iterator>
#include <utility>
#include <vector>

#include "Companion.h"
#include "utils/Decompressor.h"
#include "engine/mods/ModMetadata.h"

namespace {

// The only ROM the game supports (GameExtractor.cpp, config.yml): SHA-1 of the
// US .z64.
constexpr const char* kUsRomHash = "579c48e211ae952530ffc8738709f078d5dd215e";

// What the game requires of mk64.o2r's mods.toml (AddCoreDependencies in
// src/engine/mods/ModManager.cpp).
constexpr const char* kArchiveName = "mk64-assets";
constexpr const char* kArchiveVersionRange = "1.0.0-alpha1";

bool ReadRom(const char* path, std::vector<uint8_t>* rom) {
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) {
        return false;
    }
    rom->assign(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
    return !rom->empty();
}

} // namespace

namespace HarbourPort {

const char* GameVersion() {
    return SPAGHETTI_VERSION;
}

bool IdentifyRom(const char* path, std::string* /*description*/) {
    std::vector<uint8_t> rom;
    if (!ReadRom(path, &rom) || Companion::CalculateHash(rom) != kUsRomHash) {
        return false;
    }
    return true;
}

bool ExtractRom(const char* path, std::atomic<size_t>* done, std::atomic<size_t>* total) {
    // What GameExtractor::GenerateOTR does after the game's ROM prompts: Torch,
    // with the specs (config.yml, yamls/us, meta/mods.toml) in the framework,
    // writes mk64.o2r into the game's folder. Torch reports no progress.
    std::vector<uint8_t> rom;
    if (!ReadRom(path, &rom) || Companion::CalculateHash(rom) != kUsRomHash) {
        return false;
    }

    const std::string specsPath = Ship::Context::GetAppBundlePath();
    const std::string dataPath = Ship::Context::GetAppDirectoryPath();
    const std::filesystem::path archivePath = std::filesystem::path(dataPath) / "mk64.o2r";

    // Torch returns without an error when it finds no config or no entry for
    // the ROM, so success means a new archive afterwards.
    std::error_code error;
    const bool hadArchive = std::filesystem::exists(archivePath, error);
    const auto oldWriteTime = hadArchive ? std::filesystem::last_write_time(archivePath, error)
                                         : std::filesystem::file_time_type::min();

    // std::string, not const char*: a string literal would pick the overload
    // whose fourth parameter is a bool.
    Companion* companion = new Companion(std::move(rom), ArchiveType::O2R, false, specsPath, dataPath);
    Companion::Instance = companion;
    companion->SetAdditionalFiles({ "meta/mods.toml" });
    bool succeeded = true;
    try {
        companion->Init(ExportType::Binary);
    } catch (const std::exception& exception) {
        SDL_Log("SpaghettiKart: extraction failed: %s", exception.what());
        succeeded = false;
    } catch (...) {
        SDL_Log("SpaghettiKart: extraction failed");
        succeeded = false;
    }
    // Torch clears these itself only when it gets to the end.
    Companion::Instance = nullptr;
    delete companion;
    Decompressor::ClearCache();

    if (!succeeded || !std::filesystem::exists(archivePath, error)) {
        return false;
    }
    return !hadArchive || std::filesystem::last_write_time(archivePath, error) != oldWriteTime;
}

bool IsArchiveOutdated(const char* path) {
    // The game reads mods.toml from every archive and quits unless mk64.o2r's
    // satisfies its requirement (FindAndLoadMods, DetectOutdatedDependencies).
    zip_t* archive = zip_open(path, ZIP_RDONLY, nullptr);
    if (archive == nullptr) {
        return true;
    }
    std::string toml;
    zip_stat_t stat;
    if (zip_stat(archive, "mods.toml", 0, &stat) == 0 && (stat.valid & ZIP_STAT_SIZE) != 0) {
        if (zip_file_t* file = zip_fopen(archive, "mods.toml", 0)) {
            toml.resize(stat.size);
            if (zip_fread(file, toml.data(), stat.size) != static_cast<zip_int64_t>(stat.size)) {
                toml.clear();
            }
            zip_fclose(file);
        }
    }
    zip_close(archive);
    if (toml.empty()) {
        return true;
    }

    const ModMetadata metadata = ModMetadata::LoadFromTOML(toml);
    semver::range_set<int, int, int> range;
    semver::parse(kArchiveVersionRange, range);
    return metadata.name != kArchiveName || !range.contains(metadata.version);
}

int MenuScancode() {
    return SDL_SCANCODE_ESCAPE;
}

bool IsMenuOpen() {
    Ship::Context* context = Ship::Context::GetRawInstance();
    std::shared_ptr<Ship::Window> window = context != nullptr ? context->GetWindow() : nullptr;
    std::shared_ptr<Ship::Gui> gui = window != nullptr ? window->GetGui() : nullptr;
    return gui != nullptr && gui->GetMenuOrMenubarVisible();
}

} // namespace HarbourPort
