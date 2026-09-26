// Lighthouse's side of the engine glue. See engine/HarbourPort.h.

#include "HarbourPort.h"

#include <SDL2/SDL.h>
#include <ship/Context.h>
#include <ship/window/Window.h>
#include <ship/window/gui/Gui.h>
#include <zip.h>

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <optional>
#include <system_error>
#include <thread>

#include "port/Extractor/GameExtractor.h"
#include "port/GameVersion/BaseGameVersion.h"
#include "port/build.h"

namespace fs = std::filesystem;

namespace {

// What a ROM becomes when it's extracted. Every retail ROM makes bk.o2r, the
// base game. Once there is a current bk.o2r, a ROM of another region only adds
// its dialog instead, as a language pack in mods/~lang/, which is what the
// game's own "Add Language Pack from ROM" does. Deleting bk.o2r in the launcher
// makes the next ROM the base again.
struct ExtractionPlan {
    bool languagePack = false;
    fs::path output;
};

// The region of the base archive at `path` from the ROM CRC Torch stamps into
// its "version" file (see ReadStampedCrc in BaseGameVersion.cpp). Unstamped
// archives count as US, like the game does.
std::string ArchiveRegion(const fs::path& path) {
    zip_t* archive = zip_open(path.c_str(), ZIP_RDONLY, nullptr);
    if (archive == nullptr) {
        return "";
    }
    uint8_t data[5] = {};
    zip_int64_t length = -1;
    if (zip_file_t* file = zip_fopen(archive, "version", 0)) {
        length = zip_fread(file, data, sizeof(data));
        zip_fclose(file);
    }
    zip_close(archive);

    BKVersion version = BK_VER_US_10;
    if (length == sizeof(data)) {
        const uint32_t crc = (uint32_t)data[1] << 24 | (uint32_t)data[2] << 16 | (uint32_t)data[3] << 8 | data[4];
        Lighthouse::ClassifyArchiveVersion(crc, version);
    }
    switch (version) {
        case BK_VER_PAL:
            return "pal";
        case BK_VER_JP:
            return "jp";
        default:
            return "us";
    }
}

std::optional<ExtractionPlan> Plan(const char* path, GameExtractor& extractor) {
    // RunStandalone only accepts the four retail ROMs (by SHA-1), so romhacks,
    // which the game extracts as mods from its own menu, don't get this far.
    if (!extractor.RunStandalone(path)) {
        return std::nullopt;
    }
    ExtractionPlan plan;

    const fs::path directory = Ship::Context::GetAppDirectoryPath();
    const fs::path base = directory / "bk.o2r";
    const std::string region = extractor.GetRegionSlug();
    std::error_code error;
    const std::string baseRegion =
        fs::exists(base, error) && !HarbourPort::IsArchiveOutdated(base.c_str()) ? ArchiveRegion(base) : "";
    if (!region.empty() && !baseRegion.empty() && baseRegion != region) {
        plan.languagePack = true;
        // BK64::BKAssetFactory::PreprocessConfig names it.
        plan.output = directory / "mods" / "~lang" / ("bk" + region + ".o2r");
    } else {
        plan.output = base;
    }
    return plan;
}

// Torch reports progress per asset file: it counts parsed assets, resets the
// count, then counts exported ones, file after file. GameExtractor first counts
// the assets of all files, and Torch then overwrites that total per file. This
// turns both into one steadily growing count out of twice the overall total.
void ReportProgress(const std::atomic<size_t>& count, const std::atomic<size_t>& total,
                    const std::atomic<bool>& finished, std::atomic<size_t>* done, std::atomic<size_t>* overall) {
    size_t assets = 0;
    size_t finishedFiles = 0;
    size_t last = 0;
    while (!finished) {
        if (GameExtractor::sPhase < 2) {
            assets = std::max(assets, total.load());
        } else if (*overall == 0 && assets > 0) {
            *overall = 2 * assets;
        }
        const size_t current = count;
        if (current < last) {
            finishedFiles += last;
        }
        last = current;
        if (*overall > 0) {
            const size_t progress = std::min(finishedFiles + current, *overall - 1);
            if (progress > *done) {
                *done = progress;
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
}

} // namespace

namespace HarbourPort {

const char* GameVersion() {
    return gBuildVersion;
}

bool IdentifyRom(const char* path, std::string* description) {
    try {
        GameExtractor extractor;
        const std::optional<ExtractionPlan> plan = Plan(path, extractor);
        if (!plan) {
            return false;
        }
        // The launcher knows the dump by its checksum; only whether it becomes a language pack is news.
        *description = plan->languagePack ? "language pack" : "";
        return true;
    } catch (const std::exception& e) {
        SDL_Log("Lighthouse: can't read ROM %s: %s", path, e.what());
        return false;
    } catch (...) {
        return false;
    }
}

bool ExtractRom(const char* path, std::atomic<size_t>* done, std::atomic<size_t>* total) {
    // The steps the game's own extraction flow in GameEngine::RunExtract (and
    // the menu's language pack extraction) takes for a ROM, minus its ImGui
    // prompts. The ROM, at `path`, stays until this returns.
    try {
        GameExtractor extractor;
        const std::optional<ExtractionPlan> plan = Plan(path, extractor);
        if (!plan) {
            return false;
        }
        std::error_code error;
        if (plan->languagePack) {
            fs::create_directories(plan->output.parent_path(), error);
            extractor.SetDialogPack(true);
        }
        // Torch returns without an error on some failures, and an archive from
        // an earlier extraction may already be there.
        const auto previousWriteTime = fs::last_write_time(plan->output, error);
        const bool hadPrevious = !error;

        GameExtractor::sPhase = 0;
        std::atomic<size_t> count = 0;
        std::atomic<size_t> assets = 0;
        std::atomic<bool> finished = false;
        // A language pack only takes the dialog out of the assets GameExtractor
        // counts, so its progress stays indeterminate.
        std::thread progress;
        if (!plan->languagePack) {
            progress = std::thread(ReportProgress, std::cref(count), std::cref(assets), std::cref(finished), done, total);
        }
        auto stopProgress = [&] {
            finished = true;
            if (progress.joinable()) {
                progress.join();
            }
        };
        bool extracted = false;
        try {
            extracted = extractor.GenerateOTR(count, assets, "bk");
        } catch (...) {
            stopProgress();
            throw;
        }
        stopProgress();

        if (!extracted) {
            SDL_Log("Lighthouse: extraction failed: %s", GameExtractor::sLastError.c_str());
            return false;
        }
        const auto writeTime = fs::last_write_time(plan->output, error);
        if (error || (hadPrevious && writeTime == previousWriteTime)) {
            SDL_Log("Lighthouse: extraction didn't write %s", plan->output.c_str());
            return false;
        }
        return true;
    } catch (const std::exception& e) {
        SDL_Log("Lighthouse: extraction failed: %s", e.what());
        return false;
    } catch (...) {
        SDL_Log("Lighthouse: extraction failed");
        return false;
    }
}

bool IsArchiveOutdated(const char* path) {
    // Mirrors ReadPortVersionFromOTR and VerifyArchiveVersion in ExtractFlow.cpp,
    // which need the game's resource manager. "portVersion" in the archive holds
    // the major, minor, and patch version as big-endian 16-bit integers, and the
    // game deletes bk.o2r when major or minor differ from its own.
    zip_t* archive = zip_open(path, ZIP_RDONLY, nullptr);
    if (archive == nullptr) {
        // The game can't open it either, and replaces it.
        return true;
    }
    uint8_t data[6] = {};
    zip_int64_t length = -1;
    if (zip_file_t* file = zip_fopen(archive, "portVersion", 0)) {
        length = zip_fread(file, data, sizeof(data));
        zip_fclose(file);
    }
    zip_close(archive);

    // Like the game, treat an archive without a version as version 0.0.
    uint16_t major = 0;
    uint16_t minor = 0;
    if (length == sizeof(data)) {
        major = data[0] << 8 | data[1];
        minor = data[2] << 8 | data[3];
    }
    return major != gBuildVersionMajor || minor != gBuildVersionMinor;
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
