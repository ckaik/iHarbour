// See ConfigFile.h.

#include "ConfigFile.h"

#import <Foundation/Foundation.h>

#include <nlohmann/json.hpp>

#include <cmath>
#include <cstdio>
#include <fstream>
#include <optional>
#include <string>

namespace {

// "gSettings.InternalResolution" -> /CVars/gSettings/InternalResolution.
nlohmann::json::json_pointer SettingPointer(const char* name) {
    std::string pointer = "/CVars/";
    for (const char* c = name; *c != '\0'; c++) {
        pointer += *c == '.' ? '/' : *c;
    }
    return nlohmann::json::json_pointer(pointer);
}

// The config file, or an empty one if there is none yet. Nothing if the file
// exists but can't be read, so a damaged config is never overwritten with a
// near-empty one.
std::optional<nlohmann::json> LoadConfig(const char* path) {
    std::ifstream file(path);
    if (!file.is_open()) {
        return nlohmann::json::object();
    }
    nlohmann::json config = nlohmann::json::parse(file, nullptr, false);
    if (!config.is_object()) {
        NSLog(@"iHarbour: %s is not a JSON object; leaving it alone", path);
        return std::nullopt;
    }
    return config;
}

void SaveConfig(const char* path, const nlohmann::json& config) {
    // Formatted the way libultraship's Ship::Config::Save writes it. Written to
    // a temporary file that then replaces the config, so a write cut short
    // can't leave a truncated config behind for the game to discard.
    const std::string contents = config.dump(4);
    const std::string temporaryPath = std::string(path) + ".tmp";
    {
        std::ofstream file(temporaryPath, std::ios::trunc);
        file << contents;
        file.flush();
        if (!file.good()) {
            NSLog(@"iHarbour: could not write %s", temporaryPath.c_str());
            std::remove(temporaryPath.c_str());
            return;
        }
    }
    if (std::rename(temporaryPath.c_str(), path) != 0) {
        NSLog(@"iHarbour: could not replace %s", path);
        std::remove(temporaryPath.c_str());
    }
}

// Reads, changes, and writes back the config file. `change` returns whether it
// changed anything. Type errors (a setting path running through a value that
// isn't an object) leave the file as it was.
template <typename Change> void EditConfig(const char* path, Change change) {
    std::optional<nlohmann::json> config = LoadConfig(path);
    if (!config.has_value()) {
        return;
    }
    try {
        if (change(*config)) {
            SaveConfig(path, *config);
        }
    } catch (const nlohmann::json::exception& e) {
        NSLog(@"iHarbour: could not change %s: %s", path, e.what());
    }
}

template <typename T>
T GetSetting(const char* path, const char* name, T defaultValue, bool (nlohmann::json::*isType)() const) {
    const std::optional<nlohmann::json> config = LoadConfig(path);
    try {
        const auto pointer = SettingPointer(name);
        if (!config.has_value() || !config->contains(pointer)) {
            return defaultValue;
        }
        const nlohmann::json& value = config->at(pointer);
        return (value.*isType)() ? value.get<T>() : defaultValue;
    } catch (const nlohmann::json::exception&) { return defaultValue; }
}

template <typename T> void SetSetting(const char* path, const char* name, T value) {
    EditConfig(path, [&](nlohmann::json& config) {
        config[SettingPointer(name)] = value;
        return true;
    });
}

} // namespace

extern "C" int HarbourConfig_GetInt(const char* configPath, const char* name, int defaultValue) {
    return GetSetting<int>(configPath, name, defaultValue, &nlohmann::json::is_number_integer);
}

extern "C" float HarbourConfig_GetFloat(const char* configPath, const char* name, float defaultValue) {
    return GetSetting<float>(configPath, name, defaultValue, &nlohmann::json::is_number_float);
}

extern "C" void HarbourConfig_SetInt(const char* configPath, const char* name, int value) {
    SetSetting(configPath, name, value);
}

extern "C" void HarbourConfig_SetFloat(const char* configPath, const char* name, float value) {
    // Stored as a JSON float even when whole (1.0, not 1), or the game reads it
    // back as an integer setting and ignores it. Rounding keeps 0.8f from being
    // written as 0.800000011920929.
    SetSetting(configPath, name, std::round((double)value * 1e6) / 1e6);
}

extern "C" void HarbourConfig_Clear(const char* configPath, const char* name) {
    EditConfig(configPath, [&](nlohmann::json& config) {
        const auto pointer = SettingPointer(name);
        if (!config.contains(pointer)) {
            return false;
        }
        config.at(pointer.parent_pointer()).erase(pointer.back());
        return true;
    });
}
