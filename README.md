# Spatialite extension fork
This is a fork of the https://github.com/litehelpers/Cordova-sqlite-storage project. Some changes were made to allow the plugin to work with the *SpatiaLite* extension for SQLite.

SpatiaLite enables the SQLite database to understand and process spatial data, e.g. coordinates and shapes. For more information see https://www.gaia-gis.it/fossil/libspatialite/index

Currently, only Android and iOS are supported to work with this plugin.

# iOS native libraries

The iOS build links SpatiaLite 4.3.0a, GEOS 3.4.2, PROJ 4.8.0 and SQLite 3.8.11 as
static xcframeworks under `src/ios/native`. Each xcframework carries a device slice
(arm64) and a simulator slice (arm64 + x86_64), so apps build on Apple Silicon
simulators without excluding arm64. Deployment target of the libraries is iOS 13.0.

To rebuild them from source (for example after a toolchain change):

```
scripts/build-ios-xcframeworks.sh
```

The script downloads the pinned upstream tarballs (checksums verified), builds the
three targets and packs the xcframeworks into `src/ios/native`. Intermediate files
land in `build-ios/` (gitignored). See the script header for options.

# Swift Package Manager

The plugin ships a `Package.swift` and declares `<platform name="ios" package="swift">`.
cordova-ios 8+ and Capacitor projects that use Swift Package Manager therefore consume the
iOS part as a Swift package: the xcframeworks become binary targets and the required system
libraries (iconv, xml2, c++) are linked automatically. CocoaPods based Capacitor projects and
cordova-ios 7 ignore the attribute and keep using the classic plugin.xml tags.

Note for plugin development: `npx cap sync` rewrites the cordova-ios dependency inside the
`Package.swift` of the installed plugin copy. If the plugin is linked into an app via a symlink
(`npm install ../path`), that rewrite lands in this repository; revert it before committing.

# Installation
Use the cordova command line tool in your project folder:
```
cordova plugin add https://github.com/DisyInformationssysteme/Cordova-spatialite-storage

// alternative, if the above does not work
cordova plugin add https://github.com/DisyInformationssysteme/Cordova-spatialite-storage#master-rc
```
