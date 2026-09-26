// Reads and writes settings (CVars) in a game's config file, such as
// "Ship of Harkinian/shipofharkinian.json".
//
// Games keep their CVars under "CVars" in that file, nested by the dots in their
// names ("gSettings.InternalResolution" is CVars → gSettings →
// InternalResolution), and type them by their JSON type: 1.0 is a float setting,
// 1 an integer one, and a float setting stored as an integer reads back as the
// default. Foundation's JSONSerialization writes 1.0 as 1, so the file is edited
// with nlohmann::json, the library the games themselves use.

#ifndef HARBOUR_CONFIG_FILE_H
#define HARBOUR_CONFIG_FILE_H

#ifdef __cplusplus
extern "C" {
#endif

int HarbourConfig_GetInt(const char* configPath, const char* name, int defaultValue);
float HarbourConfig_GetFloat(const char* configPath, const char* name, float defaultValue);
void HarbourConfig_SetInt(const char* configPath, const char* name, int value);
void HarbourConfig_SetFloat(const char* configPath, const char* name, float value);
/// Removes a setting, so the game falls back to its default.
void HarbourConfig_Clear(const char* configPath, const char* name);

#ifdef __cplusplus
}
#endif

#endif // HARBOUR_CONFIG_FILE_H
