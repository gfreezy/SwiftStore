#include <sqlite3.h>

// Swift cannot call sqlite3_db_config's C variadic interface directly.
int swiftstore_sqlite_defensive(sqlite3 *db, int enabled, int *result);

// Apple exports the optional pre-update API without declaring it in sqlite3.h.
// Resolve it at runtime so unsupported OS SQLite builds fail explicitly at start.
typedef void (*swiftstore_preupdate_callback)(void *, sqlite3 *, int, const char *, const char *, sqlite3_int64, sqlite3_int64);
int swiftstore_preupdate_available(void);
int swiftstore_preupdate_register(sqlite3 *, swiftstore_preupdate_callback, void *);
int swiftstore_preupdate_count(sqlite3 *);
int swiftstore_preupdate_old(sqlite3 *, int, sqlite3_value **);
int swiftstore_preupdate_new(sqlite3 *, int, sqlite3_value **);
int swiftstore_preupdate_blobwrite(sqlite3 *);
