# Contributing

Contributions are welcome. Please keep changes focused and dependency-free where practical.

Before submitting a change, run:

```sh
./scripts/package-dmg.sh --build-only
python3 scripts/check-build-workflow.py
```

Version tags must match `CFBundleShortVersionString` in `Info.plist`.
