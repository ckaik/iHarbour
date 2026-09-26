// Ship of Harkinian's side of the engine glue. See engine/HarbourPort.h.

#include "HarbourPort.h"

#include <SDL2/SDL.h>
#include <ship/Context.h>
#include <ship/window/Window.h>
#include <ship/window/gui/Gui.h>
#include <zip.h>

#include "soh/Extractor/Extract.h"

// soh/src/boot/build.c
extern "C" const uint16_t gBuildVersionMajor;
extern "C" const char gBuildVersion[];

namespace HarbourPort {

const char* GameVersion() {
    return gBuildVersion;
}

bool IdentifyRom(const char* path, std::string* /*description*/) {
    Extractor extractor;
    if (!extractor.RunFileStandalone(path)) {
        return false;
    }
    return true;
}

bool ExtractRom(const char* path, std::atomic<size_t>* done, std::atomic<size_t>* total) {
    // The steps the game's own extraction flow in OTRGlobals::RunExtract takes
    // for a ROM passed on the command line, minus its ImGui prompts. The output
    // is oot.o2r or oot-mq.o2r.
    Extractor extractor;
    if (!extractor.RunFileStandalone(path)) {
        return false;
    }
    return extractor.CallTorch(Ship::Context::GetAppBundlePath(), Ship::Context::GetAppDirectoryPath(), done,
                               total);
}

bool IsArchiveOutdated(const char* path) {
    // Mirrors ReadPortVersionFromOTR and VerifyArchiveVersion in OTRGlobals.cpp,
    // which need the game's resource manager. An archive is a zip file, and
    // "portVersion" in it holds an endianness byte and then the major, minor,
    // and patch version as 16-bit integers.
    zip_t* archive = zip_open(path, ZIP_RDONLY, nullptr);
    if (archive == nullptr) {
        // The game can't open it either, and replaces it.
        return true;
    }
    uint8_t data[7] = {};
    zip_int64_t length = -1;
    if (zip_file_t* file = zip_fopen(archive, "portVersion", 0)) {
        length = zip_fread(file, data, sizeof(data));
        zip_fclose(file);
    }
    zip_close(archive);

    // Like the game, treat an archive without a version as version 0.
    uint16_t major = 0;
    if (length == sizeof(data)) {
        const bool isBigEndian = data[0] == 1;
        major = isBigEndian ? (data[1] << 8 | data[2]) : (data[2] << 8 | data[1]);
    }
    return major != gBuildVersionMajor;
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
