# Contributing

Thanks for helping improve `indi`! Bug reports, feature requests and pull
requests are welcome.

## Reporting bugs

Please include:

- The package version, and the Dart or Flutter version.
- The INDI server and drivers (for example, indiserver 2.1 with the
  `indi_asi_ccd` driver).
- A log of the traffic when possible. Enable it with:

  ```dart
  Logger.root.level = Level.FINEST;
  Logger.root.onRecord.listen((r) => print('${r.loggerName}: ${r.message}'));
  ```

## Development

```sh
dart pub get
dart format .                     # format
dart analyze --fatal-infos        # analyze
dart test -x integration          # unit tests
dart test -p chrome -x integration  # unit tests on the web
dart test test/client/indi_client_test.dart -N 'sendNumbers'  # a single test
```

### Integration tests

`test/integration` runs against a real indiserver with the INDI simulators.
The tests start and stop indiserver themselves and are skipped when it is not
installed. On Ubuntu:

```sh
sudo add-apt-repository ppa:mutlaqja/ppa
sudo apt install indi-bin websockify
dart test -t integration
```

### Benchmarks

```sh
dart run benchmark/blob_decode_benchmark.dart
```

## Pull requests

- Keep changes focused, and add tests for new behavior.
- Public APIs need documentation comments (the analyzer enforces it).
- CI runs formatting, analysis, the tests on every platform and on the web,
  the integration tests and the pub.dev score check; all must pass.
- Add an entry to `CHANGELOG.md` for user-visible changes.

## Releasing

1. Update `version` in `pubspec.yaml` and add the release notes to
   `CHANGELOG.md`.
2. Merge to `main`.
3. Tag the release and push the tag: `git tag v0.2.0 && git push origin v0.2.0`.
   The `Publish to pub.dev` workflow publishes it.
