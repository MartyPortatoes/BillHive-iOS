fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios beta_billhive

```sh
[bundle exec] fastlane ios beta_billhive
```

Upload BillHive to TestFlight

### ios beta_selfhive

```sh
[bundle exec] fastlane ios beta_selfhive
```

Upload SelfHive to TestFlight

### ios beta_all

```sh
[bundle exec] fastlane ios beta_all
```

Upload both apps to TestFlight

### ios release_billhive

```sh
[bundle exec] fastlane ios release_billhive
```

Submit BillHive to App Store review (uses latest TestFlight build)

### ios release_selfhive

```sh
[bundle exec] fastlane ios release_selfhive
```

Submit SelfHive to App Store review (uses latest TestFlight build)

### ios release_all

```sh
[bundle exec] fastlane ios release_all
```

Submit both apps to App Store review

### ios bump

```sh
[bundle exec] fastlane ios bump
```

Bump marketing version, e.g. fastlane bump version:1.6.0

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
