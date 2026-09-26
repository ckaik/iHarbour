// Runs a libultraship game inside the iHarbour launcher app. See HarbourEngine.h.
//
// This file is compiled into every game's framework. It only depends on SDL and
// UIKit; the game-specific parts come from HarbourPort.h.

#include "HarbourEngine.h"
#include "HarbourPort.h"

#import <UIKit/UIKit.h>

#include <SDL2/SDL.h>

#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <mutex>
#include <string>
#include <vector>

namespace {

bool sRunning = false;
bool sHasRun = false;
bool sWantTouchController = false;
SDL_Joystick* sTouchJoystick = nullptr;
std::string sDataDirectory;

UIImpactFeedbackGenerator* sHaptics = nil;
Uint32 sLastHapticTicks = 0;

std::mutex sExtractionMutex;
std::atomic<size_t> sExtractDone = 0;
std::atomic<size_t> sExtractTotal = 0;

// No C++ exception may cross the C interface into Swift, where it would end the
// app, whatever a game's code throws (std::filesystem errors, bad_alloc, ...).
template <typename Result, typename Call> Result Guarded(const char* what, Result fallback, Call call) {
    try {
        return call();
    } catch (const std::exception& e) {
        SDL_Log("HarbourEngine: %s failed: %s", what, e.what());
    } catch (...) {
        SDL_Log("HarbourEngine: %s failed with an unknown exception", what);
    }
    return fallback;
}

// Points libultraship at the game's data directory. Every game's libultraship
// patch makes Context::GetAppDirectoryPath() return SHIP_HOME on iOS. The
// variable is process-wide, and the app may have loaded more than one game's
// framework, so it's set again on the way into every call that reaches the game.
void EnterGame() {
    if (!sDataDirectory.empty()) {
        setenv("SHIP_HOME", sDataDirectory.c_str(), 1);
    }
}

// Rumble Pak -> Taptic Engine. Games rumble in short bursts, so a light impact
// per burst (rate limited) feels closer than a continuous pattern.
int SDLCALL TouchControllerRumble(void* userdata, Uint16 lowFrequency, Uint16 highFrequency) {
    const Uint16 strength = SDL_max(lowFrequency, highFrequency);
    if (strength == 0) {
        return 0;
    }
    const Uint32 now = SDL_GetTicks();
    if (now - sLastHapticTicks < 100) {
        return 0;
    }
    sLastHapticTicks = now;
    // Some games rumble from their own threads, and UIKit wants the main thread.
    // The game runs from a run loop source, not a main-queue block, so the main
    // queue keeps draining while it runs.
    const CGFloat intensity = SDL_clamp(strength / 65535.0, 0.3, 1.0);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sHaptics == nil) {
            sHaptics = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        }
        [sHaptics impactOccurredWithIntensity:intensity];
    });
    return 0;
}

int DeviceIndexForJoystick(SDL_Joystick* joystick) {
    const SDL_JoystickID instance = SDL_JoystickInstanceID(joystick);
    for (int i = 0; i < SDL_NumJoysticks(); i++) {
        if (SDL_JoystickGetDeviceInstanceID(i) == instance) {
            return i;
        }
    }
    return -1;
}

void ConnectTouchController() {
    if (sTouchJoystick != nullptr || !SDL_WasInit(SDL_INIT_JOYSTICK)) {
        return;
    }

    // A virtual joystick of type GAMECONTROLLER with one button per
    // SDL_GameControllerButton and one axis per SDL_GameControllerAxis gets an
    // identity controller mapping, so the game treats it like any other pad.
    SDL_VirtualJoystickDesc desc;
    SDL_zero(desc);
    desc.version = SDL_VIRTUAL_JOYSTICK_DESC_VERSION;
    desc.type = SDL_JOYSTICK_TYPE_GAMECONTROLLER;
    desc.naxes = SDL_CONTROLLER_AXIS_MAX;
    desc.nbuttons = SDL_CONTROLLER_BUTTON_MAX;
    desc.name = "Touch Controls";
    desc.Rumble = TouchControllerRumble;

    const int deviceIndex = SDL_JoystickAttachVirtualEx(&desc);
    if (deviceIndex < 0) {
        SDL_Log("HarbourEngine: could not attach touch controller: %s", SDL_GetError());
        return;
    }
    sTouchJoystick = SDL_JoystickOpen(deviceIndex);
    if (sTouchJoystick == nullptr) {
        SDL_Log("HarbourEngine: could not open touch controller: %s", SDL_GetError());
        SDL_JoystickDetachVirtual(deviceIndex);
    }
}

void DisconnectTouchController() {
    if (sTouchJoystick == nullptr) {
        return;
    }
    const int deviceIndex = DeviceIndexForJoystick(sTouchJoystick);
    SDL_JoystickClose(sTouchJoystick);
    sTouchJoystick = nullptr;
    if (deviceIndex >= 0) {
        SDL_JoystickDetachVirtual(deviceIndex);
    }
}

void PushKey(SDL_Scancode scancode, bool down) {
    SDL_Event event;
    SDL_zero(event);
    event.type = down ? SDL_KEYDOWN : SDL_KEYUP;
    event.key.state = down ? SDL_PRESSED : SDL_RELEASED;
    event.key.keysym.scancode = scancode;
    event.key.keysym.sym = SDL_GetKeyFromScancode(scancode);
    SDL_Window* window = SDL_GetKeyboardFocus();
    event.key.windowID = window != nullptr ? SDL_GetWindowID(window) : 0;
    SDL_PushEvent(&event);
}

void SetDataDirectory(const char* path) {
    sDataDirectory = path != nullptr ? path : "";
    if (!sDataDirectory.empty()) {
        mkdir(sDataDirectory.c_str(), 0755);
    }
    EnterGame();
}

int Run(int argc, const char* const* argv) {
    if (sHasRun) {
        return -1;
    }
    sHasRun = true;
    sRunning = true;
    EnterGame();

    // Games end the process with exit() in a few places, such as declining an
    // extraction prompt, and iOS calls it when the system connection goes away.
    // The static destructors exit() runs then tear libultraship's Context down
    // after spdlog while the game's threads still run, and crash. Registered
    // now, this runs before the destructors of everything that existed before
    // the game.
    atexit([] { _exit(0); });

    // The app, not SDL's UIApplicationDelegate, owns the process, so do the
    // setup that SDL_UIKitRunApp and SDLUIKitDelegate normally do.
    SDL_SetMainReady();
    // Also registers SDL's UIApplication lifecycle observers, which turn into
    // the SDL_APP_* events the renderer uses to stop drawing in the background.
    SDL_iPhoneSetEventPump(SDL_TRUE);

    // Relative paths games write (logs, crash dumps, some saves) must land
    // somewhere writable: the game's own folder.
    if (!sDataDirectory.empty()) {
        chdir(sDataDirectory.c_str());
    }

    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
    // Otherwise the accelerometer shows up as a joystick and takes a controller slot.
    SDL_SetHint(SDL_HINT_ACCELEROMETER_AS_JOYSTICK, "0");
    // Swipes from the screen edges need a second swipe, so they don't pull up
    // the home indicator or control center mid-game.
    SDL_SetHint(SDL_HINT_IOS_HIDE_HOME_INDICATOR, "2");

    // Bring up SDL's joystick layer early so the touch controller is already
    // connected when the game enumerates its controllers.
    SDL_InitSubSystem(SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER);
    if (sWantTouchController) {
        ConnectTouchController();
    }

    UIApplication.sharedApplication.idleTimerDisabled = YES;

    std::vector<std::string> arguments(argv, argv + argc);
    std::vector<char*> cArguments;
    for (std::string& argument : arguments) {
        cArguments.push_back(argument.data());
    }
    cArguments.push_back(nullptr);

    const int result = HarbourGame_Main(argc, cArguments.data());

    // Games leave SDL running when they return (libultraship's Context lives on
    // in a static), so shut SDL down here: that takes the game's window off
    // screen.
    if (SDL_WasInit(SDL_INIT_JOYSTICK)) {
        DisconnectTouchController();
    } else {
        sTouchJoystick = nullptr;
    }
    SDL_Quit();
    UIApplication.sharedApplication.idleTimerDisabled = NO;
    sRunning = false;
    return result;
}

bool IsRunning() {
    return sRunning;
}

bool HasRun() {
    return sHasRun;
}

void SetTouchControllerConnected(bool connected) {
    sWantTouchController = connected;
    if (!sRunning) {
        return;
    }
    if (connected) {
        ConnectTouchController();
    } else {
        DisconnectTouchController();
    }
}

void SetButton(HarbourButton button, bool pressed) {
    if (sTouchJoystick != nullptr) {
        SDL_JoystickSetVirtualButton(sTouchJoystick, button, pressed ? SDL_PRESSED : SDL_RELEASED);
    }
}

void SetAxis(HarbourAxis axis, float value) {
    if (sTouchJoystick == nullptr) {
        return;
    }
    Sint16 raw;
    if (axis == HarbourAxisTriggerLeft || axis == HarbourAxisTriggerRight) {
        // A trigger spans the whole axis, from SDL_JOYSTICK_AXIS_MIN at rest to
        // SDL_JOYSTICK_AXIS_MAX pulled all the way. The gamepad mapping rescales
        // that to 0...32767, so a raw 0 would read as a half-pulled trigger.
        const float pulled = SDL_clamp(value, 0.0f, 1.0f);
        raw = (Sint16)(SDL_JOYSTICK_AXIS_MIN + pulled * (SDL_JOYSTICK_AXIS_MAX - SDL_JOYSTICK_AXIS_MIN));
    } else {
        const float clamped = SDL_clamp(value, -1.0f, 1.0f);
        raw = (Sint16)(clamped < 0 ? clamped * -SDL_JOYSTICK_AXIS_MIN : clamped * SDL_JOYSTICK_AXIS_MAX);
    }
    SDL_JoystickSetVirtualAxis(sTouchJoystick, axis, raw);
}

void ToggleMenu() {
    if (!sRunning) {
        return;
    }
    const SDL_Scancode scancode = (SDL_Scancode)HarbourPort::MenuScancode();
    PushKey(scancode, true);
    PushKey(scancode, false);
}

bool IsMenuOpen() {
    return sRunning && Guarded("IsMenuOpen", false, [] { return HarbourPort::IsMenuOpen(); });
}

bool IdentifyRom(const char* path, char* description, int descriptionSize) {
    EnterGame();
    std::string text;
    const bool supported =
        Guarded("IdentifyRom", false, [&] { return HarbourPort::IdentifyRom(path, &text); });
    if (description != nullptr && descriptionSize > 0) {
        const size_t length = std::min(text.size(), (size_t)descriptionSize - 1);
        memcpy(description, text.data(), length);
        description[length] = '\0';
    }
    return supported;
}

bool ExtractRom(const char* path) {
    std::lock_guard<std::mutex> lock(sExtractionMutex);
    EnterGame();
    sExtractDone = 0;
    sExtractTotal = 0;
    const bool extracted =
        Guarded("ExtractRom", false, [&] { return HarbourPort::ExtractRom(path, &sExtractDone, &sExtractTotal); });
    sExtractDone = sExtractTotal.load();
    return extracted;
}

float ExtractionProgress() {
    const size_t total = sExtractTotal;
    if (total == 0) {
        return -1.0f;
    }
    return SDL_min(1.0f, (float)sExtractDone / (float)total);
}

bool IsArchiveOutdated(const char* path) {
    EnterGame();
    // An archive the game can't even check is as good as outdated.
    return Guarded("IsArchiveOutdated", true, [&] { return HarbourPort::IsArchiveOutdated(path); });
}

} // namespace

extern "C" const HarbourEngineAPI* HarbourEngine_GetAPI(void) {
    static const HarbourEngineAPI api = {
        .version = HARBOUR_ENGINE_API_VERSION,
        .gameId = HARBOUR_GAME_ID,
        .gameVersion = HarbourPort::GameVersion(),
        .setDataDirectory = SetDataDirectory,
        .run = Run,
        .isRunning = IsRunning,
        .hasRun = HasRun,
        .setTouchControllerConnected = SetTouchControllerConnected,
        .setButton = SetButton,
        .setAxis = SetAxis,
        .toggleMenu = ToggleMenu,
        .isMenuOpen = IsMenuOpen,
        .identifyRom = IdentifyRom,
        .extractRom = ExtractRom,
        .extractionProgress = ExtractionProgress,
        .isArchiveOutdated = IsArchiveOutdated,
    };
    return &api;
}
