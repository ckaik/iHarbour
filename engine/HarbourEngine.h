// The interface between the iHarbour launcher app and a game.
//
// Every game builds as a framework of its own (ShipOfHarkinian.framework,
// Starship.framework, ...). Each exports exactly one symbol,
// HarbourEngine_GetAPI, which returns a table of the functions below. The app
// dlopen()s a game's framework when it first needs it and calls the game only
// through that table, so all games share this one header and the app links none
// of them.
//
// This header is plain C and is shared by the frameworks (engine/HarbourEngine.mm
// implements it) and the app (which imports it through its bridging header).

#ifndef HARBOUR_ENGINE_H
#define HARBOUR_ENGINE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Bumped whenever HarbourEngineAPI changes. The app refuses frameworks built
/// against another version.
#define HARBOUR_ENGINE_API_VERSION 1

/// Buttons of the on-screen gamepad. The values match SDL_GameControllerButton,
/// so the game sees an ordinary controller and its default mapping applies.
typedef enum HarbourButton {
    HarbourButtonA = 0,
    HarbourButtonB = 1,
    HarbourButtonX = 2,
    HarbourButtonY = 3,
    HarbourButtonBack = 4,
    HarbourButtonGuide = 5,
    HarbourButtonStart = 6,
    HarbourButtonLeftStick = 7,
    HarbourButtonRightStick = 8,
    HarbourButtonLeftShoulder = 9,
    HarbourButtonRightShoulder = 10,
    HarbourButtonDPadUp = 11,
    HarbourButtonDPadDown = 12,
    HarbourButtonDPadLeft = 13,
    HarbourButtonDPadRight = 14,
} HarbourButton;

/// Axes of the on-screen gamepad, matching SDL_GameControllerAxis.
typedef enum HarbourAxis {
    HarbourAxisLeftX = 0,
    HarbourAxisLeftY = 1,
    HarbourAxisRightX = 2,
    HarbourAxisRightY = 3,
    HarbourAxisTriggerLeft = 4,
    HarbourAxisTriggerRight = 5,
} HarbourAxis;

typedef struct HarbourEngineAPI {
    /// HARBOUR_ENGINE_API_VERSION of the framework.
    uint32_t version;
    /// The game's id in iHarbour ("soh", "2ship", ...), matching its folder in ports/.
    const char* gameId;
    /// The version of the game the framework was built from ("9.2.3").
    const char* gameVersion;

    /// Sets the directory the game reads its archives and config from and writes
    /// saves, logs and mods to. Call it before anything else; the directory is
    /// created if needed.
    void (*setDataDirectory)(const char* path);

    /// Runs the game on the main thread and returns when it quits.
    ///
    /// Start it from a run loop source (RunLoop.main.perform), not from a block
    /// on the main dispatch queue or a main actor task: the call doesn't return
    /// while the game runs, and SDL keeps the run loop turning from inside it,
    /// but a main-queue block that never finishes stalls that queue for good.
    ///
    /// The game keeps global state it never tears down, so it can run once per
    /// process. Later calls return -1.
    int (*run)(int argc, const char* const* argv);
    /// Whether run() is executing.
    bool (*isRunning)(void);
    /// Whether run() has been called in this process.
    bool (*hasRun)(void);

    /// Connects or disconnects the on-screen gamepad, an SDL game controller named
    /// "Touch Controls". Safe to call before run(); it then connects as the game
    /// starts.
    void (*setTouchControllerConnected)(bool connected);
    /// Presses or releases a button on the on-screen gamepad.
    void (*setButton)(HarbourButton button, bool pressed);
    /// Moves an axis of the on-screen gamepad. Sticks take -1...1 (y grows
    /// downwards, like SDL), triggers take 0...1.
    void (*setAxis)(HarbourAxis axis, float value);

    /// Opens or closes the game's menu, like the key the game uses for it.
    void (*toggleMenu)(void);
    /// Whether the game's menu or menu bar is open.
    bool (*isMenuOpen)(void);

    /// Checks the ROM at `path` (a .z64 file) with the game's own checks. Writes
    /// what only the game can tell about it ("language pack"; usually nothing)
    /// into `description` and returns true if the game can extract it. Reads the whole
    /// file, so call it off the main thread.
    bool (*identifyRom)(const char* path, char* description, int descriptionSize);
    /// Extracts the game's assets from the ROM at `path` into the data directory,
    /// replacing an existing archive. Blocks for up to a few minutes, so call it
    /// off the main thread, and never while the game runs. One extraction runs at
    /// a time; a second call waits for the first.
    bool (*extractRom)(const char* path);
    /// Progress of the running extraction, 0...1, or a negative value if the
    /// extractor doesn't report progress.
    float (*extractionProgress)(void);

    /// Whether the archive at `path` came from a version of the game this one
    /// can't load, so the ROM needs extracting again.
    bool (*isArchiveOutdated)(const char* path);
} HarbourEngineAPI;

typedef const HarbourEngineAPI* (*HarbourEngineGetAPIFunction)(void);

/// The one symbol a game framework exports.
__attribute__((visibility("default"))) const HarbourEngineAPI* HarbourEngine_GetAPI(void);

#ifdef __cplusplus
}
#endif

#endif // HARBOUR_ENGINE_H
