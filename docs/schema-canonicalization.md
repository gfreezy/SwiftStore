# Canonical schema comparison

Migration generation and `check` canonicalize schema snapshots before comparing them.
`SchemaSnapshot.json()` also canonicalizes before encoding, so migration checksums use the
same representation. `SchemaSnapshot.isEquivalent(to:)` exposes this comparison to callers.

Canonicalization is specific to schema metadata; it does not modify Entity JSON or migration
Swift source. Decoding resolves field defaults, then `canonicalized()` normalizes table order
and validates the resulting schema. Column order, compound-index column order, SQL expressions,
and string literals are preserved.

| Metadata | Rules |
| --- | --- |
| Table `indexes`, `triggers`, `foreignKeys`, `fullTextIndexes` | Missing, JSON `null`, and `[]` all mean no entries. `{}` and `""` are type errors. |
| Required table/index/FTS columns and FTS identity columns | Missing, `null`, and `[]` normalize to empty, then fail schema validation. |
| Column `defaultValue` and `generatedAs` | Missing and JSON `null` mean absent. Empty SQL expressions are invalid. SQL `NULL` and SQL `''` remain distinct. |
| Names, column types, foreign-key references | Required and nonempty; missing/null values are rejected. |
| `isNullable`, `isPrimaryKey`, `isUnique` | Missing defaults to `false`; explicit `null` and non-boolean values are rejected. |
| FTS `tokenizer` | Missing defaults to `unicode61`; null, empty and unknown values are rejected. |
| Foreign-key `onDelete` and `onUpdate` | Missing defaults to `NO ACTION`; null and unknown values are rejected. |
| Table/index auxiliary `sql` | Missing, null and empty mean that no original CREATE statement was captured. Nonempty SQL is preserved. |

All collections are encoded explicitly, including empty `fullTextIndexes: []`. There is no
legacy-encoding compatibility path. Migration source still participates byte-for-byte in the
checksum; canonicalization never conceals source edits or substantive schema changes.
