// PaperBoat's side of the engine glue. See engine/HarbourPort.h.

#include "HarbourPort.h"

#include <SDL2/SDL.h>
#include <ship/Context.h>
#include <ship/window/Window.h>
#include <ship/window/gui/Gui.h>

#include <exception>
#include <filesystem>
#include <string>

#include "port/build.h"
#include "port/extractor/GameExtractor.h"

namespace {

// What config.yml tells Torch to write for the one ROM it has a recipe for.
constexpr const char* kGameArchive = "pm64.o2r";
// Torch's record of the YAMLs it has extracted, kept next to the archive.
constexpr const char* kTorchHashes = "torch.hash.yml";

} // namespace

namespace HarbourPort {

const char* GameVersion() {
    static const std::string version = std::to_string(gBuildVersionMajor) + "." +
                                       std::to_string(gBuildVersionMinor) + "." +
                                       std::to_string(gBuildVersionPatch);
    return version.c_str();
}

bool IdentifyRom(const char* path, std::string* /*description*/) {
    // The check GameExtractor::RunStandalone makes: config.yml, in the
    // framework, has a recipe for the ROM's SHA-1. Only the US ROM has one.
    try {
        if (!GameExtractor::DetectVersion(path, Ship::Context::GetAppBundlePath()).has_value()) {
            return false;
        }
    } catch (const std::exception& error) {
        SDL_Log("PaperBoat: could not identify %s: %s", path, error.what());
        return false;
    }
    return true;
}

bool ExtractRom(const char* path, std::atomic<size_t>* done, std::atomic<size_t>* total) {
    // The steps the Android launcher takes (src/port/android/AndroidBridge.cpp),
    // which the desktop flow in GameEngine::RunExtract also comes down to. Torch
    // reads config.yml and assets/ from the framework and writes pm64.o2r into
    // the game's folder.
    const std::string sourceDirectory = Ship::Context::GetAppBundlePath();
    const std::filesystem::path gameDirectory = Ship::Context::GetAppDirectoryPath();
    const std::filesystem::path archive = gameDirectory / kGameArchive;
    const std::filesystem::path torchHashes = gameDirectory / kTorchHashes;

    // Torch builds the archive in memory and writes it only at the very end, so
    // an archive from an earlier extraction survives a failed one. It's how a
    // failure that Torch only logs is told apart from success: the archive must
    // be new.
    std::error_code error;
    const bool hadArchive = std::filesystem::exists(archive, error);
    const std::filesystem::file_time_type previousWrite =
        hadArchive ? std::filesystem::last_write_time(archive, error) : std::filesystem::file_time_type();

    bool extracted = false;
    try {
        GameExtractor extractor;
        if (!extractor.RunStandalone(path, sourceDirectory)) {
            SDL_Log("PaperBoat: %s is not a supported ROM", path);
            return false;
        }
        // Torch skips every YAML that torch.hash.yml lists as extracted already,
        // so with one left from an earlier run the new archive would come out
        // empty.
        std::filesystem::remove(torchHashes, error);
        // Progress counts the asset YAMLs Torch has processed.
        extracted = extractor.GenerateOTRTo(*done, *total, sourceDirectory, gameDirectory.string());
        if (!extracted) {
            SDL_Log("PaperBoat: Torch could not extract the ROM: %s", GameExtractor::sLastError.c_str());
        }
    } catch (const std::exception& exception) {
        SDL_Log("PaperBoat: Torch could not extract the ROM: %s", exception.what());
    } catch (...) {
        SDL_Log("PaperBoat: Torch could not extract the ROM");
    }
    std::filesystem::remove(torchHashes, error);

    if (!extracted || !std::filesystem::exists(archive, error) || std::filesystem::file_size(archive, error) == 0) {
        return false;
    }
    if (hadArchive && std::filesystem::last_write_time(archive, error) == previousWrite) {
        SDL_Log("PaperBoat: Torch finished without writing %s", kGameArchive);
        return false;
    }
    return true;
}

bool IsArchiveOutdated(const char* path) {
    // pm64.o2r carries a portVersion, but the game never reads it back.
    return false;
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
