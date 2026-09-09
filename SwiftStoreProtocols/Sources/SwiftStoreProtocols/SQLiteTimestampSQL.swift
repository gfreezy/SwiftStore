/// Unix seconds with millisecond precision, including on iOS 16 SQLite.
/// Prefer native subsec; SQLite versions returning NULL use %s epoch seconds
/// plus the fractional suffix of %f. Both branches produce REAL Unix seconds.
public enum SQLiteTimestampSQL {
    public static let now = "(COALESCE(unixepoch('subsec'), CAST(strftime('%s', 'now') AS REAL) + CAST(substr(strftime('%f', 'now'), 3) AS REAL)))"
}
