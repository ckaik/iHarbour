// What a game provides to the shared engine glue (engine/HarbourEngine.mm).
//
// Each game implements these in ports/<game>/, which harbour_add_game_framework()
// compiles into the game's framework next to engine/. Everything that depends on
// the game or on its version of libultraship lives there; engine/ only uses SDL.

#ifndef HARBOUR_PORT_H
#define HARBOUR_PORT_H

#include <atomic>
#include <cstddef>
#include <string>

// The game's main(), renamed by the game's patch.
extern "C" int HarbourGame_Main(int argc, char* argv[]);

namespace HarbourPort {

/// The game's version, for display ("9.2.3").
const char* GameVersion();

/// Whether the game can extract the ROM at `path`, and what only the game can
/// tell about it ("language pack"; the launcher names the dump by its checksum).
/// `path` is a .z64 file (the launcher converts byte-swapped ROMs first).
bool IdentifyRom(const char* path, std::string* description);

/// Extracts the ROM at `path` into the game's data directory
/// (Ship::Context::GetAppDirectoryPath(), which the engine points at the game's
/// folder). Reports progress through `done` and `total` if it can; leaving
/// `total` at 0 means no progress. Runs on a background thread.
bool ExtractRom(const char* path, std::atomic<size_t>* done, std::atomic<size_t>* total);

/// Whether the archive at `path` came from an older version of the game.
bool IsArchiveOutdated(const char* path);

/// The SDL scancode that opens and closes the game's menu.
int MenuScancode();

/// Whether the game's menu is open. Only called while the game runs.
bool IsMenuOpen();

} // namespace HarbourPort

#endif // HARBOUR_PORT_H
