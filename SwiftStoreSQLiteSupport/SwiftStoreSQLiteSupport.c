#include "SwiftStoreSQLiteSupport.h"

#include <dlfcn.h>
#include <pthread.h>

static void *(*preupdate_register)(sqlite3 *, swiftstore_preupdate_callback, void *);
static int (*preupdate_count)(sqlite3 *);
static int (*preupdate_old)(sqlite3 *, int, sqlite3_value **);
static int (*preupdate_new)(sqlite3 *, int, sqlite3_value **);
static int (*preupdate_blobwrite)(sqlite3 *);
static pthread_once_t preupdate_once = PTHREAD_ONCE_INIT;

static void resolve_preupdate(void) {
    preupdate_register = dlsym(RTLD_DEFAULT, "sqlite3_preupdate_hook");
    preupdate_count = dlsym(RTLD_DEFAULT, "sqlite3_preupdate_count");
    preupdate_old = dlsym(RTLD_DEFAULT, "sqlite3_preupdate_old");
    preupdate_new = dlsym(RTLD_DEFAULT, "sqlite3_preupdate_new");
    preupdate_blobwrite = dlsym(RTLD_DEFAULT, "sqlite3_preupdate_blobwrite");
}

int swiftstore_preupdate_available(void) {
    pthread_once(&preupdate_once, resolve_preupdate);
    return preupdate_register && preupdate_count && preupdate_old && preupdate_new && preupdate_blobwrite;
}

int swiftstore_preupdate_register(sqlite3 *db, swiftstore_preupdate_callback callback, void *context) {
    if (!swiftstore_preupdate_available()) return SQLITE_NOTFOUND;
    preupdate_register(db, callback, context);
    return SQLITE_OK;
}
int swiftstore_preupdate_count(sqlite3 *db) { return preupdate_count(db); }
int swiftstore_preupdate_old(sqlite3 *db, int column, sqlite3_value **value) { return preupdate_old(db, column, value); }
int swiftstore_preupdate_new(sqlite3 *db, int column, sqlite3_value **value) { return preupdate_new(db, column, value); }
int swiftstore_preupdate_blobwrite(sqlite3 *db) { return preupdate_blobwrite(db); }
