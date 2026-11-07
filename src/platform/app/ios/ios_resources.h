#ifndef IOS_RESOURCES_H
#define IOS_RESOURCES_H

#include <stdbool.h>

// Returned path has a trailing slash and remains owned by the application.
const char* IOSResources_GetDocumentsPath(void);
bool IOSResources_RunImportFlow(void);

#endif
