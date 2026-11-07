#include "port/paths.h"

#include <SDL3/SDL.h>

#if CRS_PLATFORM_IOS
#include "platform/app/ios/ios_resources.h"
#endif

#define ORG "CrowdedStreet"
#define APP "3SX"

static const char* pref_path = NULL;

const char* Paths_GetPrefPath() {
    if (pref_path == NULL) {
#if CRS_PLATFORM_IOS
        // Documents is visible in Files and Finder when file sharing is enabled.
        pref_path = IOSResources_GetDocumentsPath();
#else
        pref_path = SDL_GetPrefPath(ORG, APP);
#endif
    }

    return pref_path;
}

char* Paths_GetCachePath(const char* file_path) {
    const char* base = Paths_GetPrefPath();
    char* full_path = NULL;

    if (file_path == NULL) {
        SDL_asprintf(&full_path, "%scache/", base);
    } else {
        SDL_asprintf(&full_path, "%scache/%s", base, file_path);
    }

    return full_path;
}

const char* Paths_GetBasePath() {
    return SDL_GetBasePath();
}

SDL_Storage* Paths_OpenUserStorage(SDL_PropertiesID props) {
    return SDL_OpenUserStorage(ORG, APP, props);
}
