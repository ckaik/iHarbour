// Ghostship's side of the engine glue. See engine/HarbourPort.h.

#include "HarbourPort.h"

#include <SDL2/SDL.h>
#include <ship/Context.h>
#include <ship/window/Window.h>
#include <ship/window/gui/Gui.h>
#include <spdlog/spdlog.h>
#include <yaml-cpp/yaml.h>
#include <zip.h>

#include <exception>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <vector>

#include "Companion.h"
#include "port/GameExtractor.h"
#include "port/ShipCompat.h"

// src/port/build.c
extern "C" const uint16_t gBuildVersionMajor;
extern "C" const uint16_t gBuildVersionMinor;
extern "C" const char gBuildVersion[];

namespace fs = std::filesystem;

namespace {

// include/sm64.h: the CRCs of the ROMs sm64.o2r can come from.
constexpr uint32_t kGameVersionUS = 0xFF2B5A63;
constexpr uint32_t kGameVersionJP = 0x0E3DAA4E;

std::vector<uint8_t> ReadFile(const fs::path& path) {
    std::ifstream file(path, std::ios::binary);
    return std::vector<uint8_t>(std::istreambuf_iterator<char>(file), {});
}

std::vector<uint8_t> ReadArchiveEntry(zip_t* archive, const char* name) {
    std::vector<uint8_t> data;
    zip_stat_t stat;
    if (zip_stat(archive, name, 0, &stat) != 0 || !(stat.valid & ZIP_STAT_SIZE)) {
        return data;
    }
    if (zip_file_t* file = zip_fopen(archive, name, 0)) {
        data.resize(stat.size);
        const zip_int64_t length = zip_fread(file, data.data(), data.size());
        data.resize(length > 0 ? length : 0);
        zip_fclose(file);
    }
    return data;
}

// The YAML specs Torch works through for the ROM with this SHA-1: the files
// Companion::Process picks from the folder config.yml names for it.
size_t CountAssetSpecs(const fs::path& sourceDirectory, const std::string& romHash) {
    YAML::Node config = YAML::LoadFile((sourceDirectory / "config.yml").string());
    if (!config[romHash] || !config[romHash]["path"]) {
        return 0;
    }
    size_t count = 0;
    std::error_code error;
    for (const auto& entry :
         fs::recursive_directory_iterator(sourceDirectory / config[romHash]["path"].as<std::string>(), error)) {
        const std::string name = entry.path().filename().string();
        const std::string extension = entry.path().extension().string();
        if (entry.is_regular_file() && (extension == ".yml" || extension == ".yaml") && name != "config.yml" &&
            name != "hashes.yaml") {
            count++;
        }
    }
    return count;
}

} // namespace

namespace HarbourPort {

const char* GameVersion() {
    return gBuildVersion;
}

bool IdentifyRom(const char* path, std::string* /*description*/) {
    return GameExtractor::DetectVersion(path).has_value();
}

bool ExtractRom(const char* path, std::atomic<size_t>* done, std::atomic<size_t>* total) {
    // What GameEngine::RunExtract does with a ROM it finds, minus its ImGui
    // prompts: GameExtractor::RunStandalone, then GenerateOTRTo, written out here
    // to count progress. Torch reads config.yml and assets/ymls from the
    // framework and writes sm64.o2r, for either version.
    const fs::path sourceDirectory = Ship::Context::GetAppBundlePath();
    const fs::path dataDirectory = Ship::Context::GetAppDirectoryPath();
    // Torch writes into a fresh folder: it skips every spec torch.hash.yml in its
    // output folder lists as extracted, which would leave a second extraction
    // with an almost empty archive. The old archive also stays in place until
    // the new one is complete.
    const fs::path workDirectory = dataDirectory / ".extract";
    std::error_code error;

    bool extracted = false;
    try {
        if (!GameExtractor::DetectVersion(path).has_value()) {
            return false;
        }
        std::vector<uint8_t> rom = ReadFile(path);
        *total = CountAssetSpecs(sourceDirectory, Companion::CalculateHash(rom));

        fs::remove_all(workDirectory, error);
        fs::create_directories(workDirectory);

        // Never deleted, like on every other platform: ~Companion double-frees.
        Companion::Instance = new Companion(std::move(rom), ArchiveType::O2R, false, sourceDirectory.string(),
                                            workDirectory.string());
        GameExtractor().WritePortVersion();
        // Torch counts assets per spec file and starts again at 0 for each, so
        // count the specs as they reach their export phase instead.
        Companion::Instance->SetPhaseCallback([done](int phase) {
            if (phase == 2) {
                (*done)++;
            }
        });
        std::atomic<size_t> assetCount{ 0 };
        Companion::Instance->Init(ExportType::Binary, assetCount, true);

        // Torch logs and returns without writing anything on some errors.
        const fs::path archive = workDirectory / "sm64.o2r";
        if (fs::exists(archive, error) && fs::file_size(archive, error) > 0) {
            fs::rename(archive, dataDirectory / "sm64.o2r");
            // The game's "regenerate the archive" marker, done now.
            fs::remove(dataDirectory / "regenerate_o2r", error);
            extracted = true;
        } else {
            SPDLOG_ERROR("Torch finished without writing {}", archive.string());
        }
    } catch (const std::exception& exception) {
        SPDLOG_ERROR("Extracting {} failed: {}", path, exception.what());
    } catch (...) {
        SPDLOG_ERROR("Extracting {} failed", path);
    }
    fs::remove_all(workDirectory, error);
    return extracted;
}

bool IsArchiveOutdated(const char* path) {
    // Mirrors what GameEngine::RunExtract checks before it loads sm64.o2r
    // (ReadPortVersionFromOTR, VerifyArchiveVersion, IsArchiveGameVersionUnknown),
    // which need the game's resource manager.

    // "Regenerate game assets" leaves this marker, and the game then deletes the
    // archive on its next start.
    std::error_code error;
    if (fs::exists(fs::path(Ship::Context::GetAppDirectoryPath()) / "regenerate_o2r", error)) {
        return true;
    }

    zip_t* archive = zip_open(path, ZIP_RDONLY, nullptr);
    if (archive == nullptr) {
        // The game would set it aside and ask for the ROM.
        return true;
    }
    const std::vector<uint8_t> portVersion = ReadArchiveEntry(archive, "portVersion");
    const std::vector<uint8_t> romVersion = ReadArchiveEntry(archive, "version");
    zip_close(archive);

    // "portVersion" holds the game version that wrote the archive as big-endian
    // 16-bit major, minor and patch numbers. Major and minor must match. The game
    // lets an archive without one (0.0.0) through.
    if (portVersion.size() >= 6) {
        const uint16_t major = portVersion[0] << 8 | portVersion[1];
        const uint16_t minor = portVersion[2] << 8 | portVersion[3];
        const uint16_t patch = portVersion[4] << 8 | portVersion[5];
        const bool unversioned = major == 0 && minor == 0 && patch == 0;
        if (!unversioned && (major != gBuildVersionMajor || minor != gBuildVersionMinor)) {
            return true;
        }
    }

    // "version" holds an endianness byte and the ROM's CRC, which must be one the
    // game knows, in either byte order.
    if (romVersion.size() >= 5) {
        const uint32_t crc = (uint32_t)romVersion[1] << 24 | romVersion[2] << 16 | romVersion[3] << 8 | romVersion[4];
        const uint32_t swapped = __builtin_bswap32(crc);
        const bool known = crc == kGameVersionUS || crc == kGameVersionJP || swapped == kGameVersionUS ||
                           swapped == kGameVersionJP;
        if (!known) {
            return true;
        }
    }
    return false;
}

int MenuScancode() {
    return SDL_SCANCODE_ESCAPE;
}

bool IsMenuOpen() {
    std::shared_ptr<Ship::Window> window = ShipCompat::GetWindow();
    std::shared_ptr<Ship::Gui> gui = window != nullptr ? window->GetGui() : nullptr;
    return gui != nullptr && gui->GetMenuOrMenubarVisible();
}

} // namespace HarbourPort
