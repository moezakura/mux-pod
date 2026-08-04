# Agent Notes

## Verification Commands

```bash
make analyze   # flutter analyze
make test      # flutter test
make build-apk # flutter build apk --release --dart-define=GIT_REF=...
```

## Notes

- `make build-apk` in this checkout fails at the packaging step because `android/app/upload-keystore.jks` is not present. Compilation itself succeeds; this is a signing/keystore environment issue, not a code issue.
- `analysis_options.yaml` should not globally ignore `deprecated_member_use_from_same_package`. Deprecated alias tests use `// ignore_for_file: deprecated_member_use_from_same_package` instead.
- Connection settings are stored in `multiplexer` (backend + executablePath) form. Legacy `tmuxPath` is migrated on startup via `ConnectionMigration`.
