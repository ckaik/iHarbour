// 2 Ship 2 Harkinian's side of the engine glue. See engine/HarbourPort.h.

#include "HarbourPort.h"

#include <SDL2/SDL.h>
#include <ship/Context.h>
#include <ship/window/Window.h>
#include <ship/window/gui/Gui.h>
#include <zip.h>

#include <cstdio>
#include <filesystem>
#include <set>

#include "2s2h/Extractor/Extract.h"

// mm/src/boot/build.c
extern "C" const uint16_t gBuildVersionMajor;
extern "C" const char gBuildVersion[];

namespace {

// The ROMs the game can extract, by the CRC in their header (big-endian, at 0x10).
// The same as verMap in Extract.cpp and validHashes in BenPort.cpp.
constexpr uint32_t kRomUS = 0x5354631C;
constexpr uint32_t kRomGCUS = 0xB443EB08;

uint32_t ReadBigEndian32(const uint8_t* data) {
    return (uint32_t)data[0] << 24 | (uint32_t)data[1] << 16 | (uint32_t)data[2] << 8 | data[3];
}

// Reads the file `name` from `archive` if it is exactly `size` bytes.
bool ReadArchiveFile(zip_t* archive, const char* name, uint8_t* data, zip_int64_t size) {
    zip_file_t* file = zip_fopen(archive, name, 0);
    if (file == nullptr) {
        return false;
    }
    const zip_int64_t length = zip_fread(file, data, size);
    zip_fclose(file);
    return length == size;
}

// The extractor's temporary directories (Extractor::Mkdtemp).
std::set<std::filesystem::path> ExtractorTempDirectories() {
    std::set<std::filesystem::path> directories;
    std::error_code error;
    for (const auto& entry : std::filesystem::directory_iterator(std::filesystem::temp_directory_path(), error)) {
        if (entry.path().filename().string().starts_with("extractor-")) {
            directories.insert(entry.path());
        }
    }
    return directories;
}

// Whether `extractor` accepts the ROM at `path`, which also loads it. Sets `crc`
// to the CRC in its header, which tells the versions apart.
bool LoadRom(Extractor& extractor, const char* path, uint32_t* crc) {
    // The launcher hands over big-endian .z64 files. Anything else could make
    // Extractor::RunFileStandalone show an SDL message box ("File is Compressed"),
    // and this runs on a background thread.
    uint8_t header[0x14] = {};
    FILE* file = fopen(path, "rb");
    if (file == nullptr) {
        return false;
    }
    const size_t length = fread(header, 1, sizeof(header), file);
    fclose(file);
    if (length != sizeof(header) || ReadBigEndian32(header) != 0x80371240) {
        return false;
    }
    *crc = ReadBigEndian32(header + 0x10);
    // Checks the size and the CRC of the whole ROM against the dumps the game supports.
    try {
        return extractor.RunFileStandalone(path);
    } catch (const std::exception& exception) {
        SDL_Log("2 Ship 2 Harkinian: can't read %s: %s", path, exception.what());
        return false;
    }
}

} // namespace

namespace HarbourPort {

const char* GameVersion() {
    return gBuildVersion;
}

bool IdentifyRom(const char* path, std::string* /*description*/) {
    Extractor extractor;
    uint32_t crc = 0;
    if (!LoadRom(extractor, path, &crc)) {
        return false;
    }
    return crc == kRomUS || crc == kRomGCUS;
}

bool ExtractRom(const char* path, std::atomic<size_t>* done, std::atomic<size_t>* total) {
    // The steps the game's own extraction flow in OTRGlobals::RunExtract takes
    // for a ROM passed on the command line, minus its ImGui prompts. ZAPD
    // writes mm.o2r into a temporary directory, which CallZapd makes the
    // current directory, and then copies it into the game's folder.
    Extractor extractor;
    uint32_t crc = 0;
    if (!LoadRom(extractor, path, &crc) || (crc != kRomUS && crc != kRomGCUS)) {
        return false;
    }

    const std::string dataDirectory = Ship::Context::GetAppDirectoryPath();
    const std::filesystem::path archive = std::filesystem::path(dataDirectory) / "mm.o2r";
    std::error_code error;
    const std::filesystem::path currentDirectory = std::filesystem::current_path(error);
    const std::set<std::filesystem::path> previousTempDirectories = ExtractorTempDirectories();
    // ZAPD throws on bad data, and CallZapd then leaves the process in its
    // temporary directory and the directory behind.
    auto cleanUp = [&] {
        std::filesystem::current_path(currentDirectory, error);
        for (const std::filesystem::path& directory : ExtractorTempDirectories()) {
            if (!previousTempDirectories.contains(directory)) {
                std::filesystem::remove_all(directory, error);
            }
        }
    };
    try {
        // Returns false whether or not it worked.
        extractor.CallZapd(Ship::Context::GetAppBundlePath(), dataDirectory, done, total);
    } catch (const std::exception& exception) {
        SDL_Log("2 Ship 2 Harkinian: extraction failed: %s", exception.what());
        cleanUp();
        return false;
    } catch (...) {
        SDL_Log("2 Ship 2 Harkinian: extraction failed");
        cleanUp();
        return false;
    }
    // CallZapd's last step copies the new archive over any old one and throws
    // if ZAPD didn't write it, so here it's the new one.
    return std::filesystem::exists(archive, error);
}

bool IsArchiveOutdated(const char* path) {
    // Mirrors DetectArchiveVersion, VerifyArchiveVersion (BenPort.cpp), which
    // need the game's resource manager, and the check of the ROM hash in
    // OTRGlobals::Initialize, which quits the game. An archive is a zip file.
    // "portVersion" in it holds an endianness byte and then the major, minor,
    // and patch version as 16-bit integers; "version" holds an endianness byte
    // and the CRC of the ROM it came from.
    zip_t* archive = zip_open(path, ZIP_RDONLY, nullptr);
    if (archive == nullptr) {
        // The game can't read its version either, and replaces it.
        return true;
    }
    uint8_t portVersion[7] = {};
    const bool hasPortVersion = ReadArchiveFile(archive, "portVersion", portVersion, sizeof(portVersion));
    uint8_t romVersion[5] = {};
    const bool hasRomVersion = ReadArchiveFile(archive, "version", romVersion, sizeof(romVersion));
    zip_close(archive);

    // Like the game, treat an archive without a version as version 0.
    uint16_t major = 0;
    if (hasPortVersion) {
        const bool isBigEndian = portVersion[0] == 1;
        major = isBigEndian ? (portVersion[1] << 8 | portVersion[2]) : (portVersion[2] << 8 | portVersion[1]);
    }
    if (major != gBuildVersionMajor) {
        return true;
    }

    if (hasRomVersion) {
        const bool isBigEndian = romVersion[0] == 1;
        const uint32_t crc = isBigEndian ? ReadBigEndian32(romVersion + 1)
                                         : (uint32_t)romVersion[4] << 24 | (uint32_t)romVersion[3] << 16 |
                                               (uint32_t)romVersion[2] << 8 | romVersion[1];
        if (crc != kRomUS && crc != kRomGCUS) {
            return true;
        }
    }
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
