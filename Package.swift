// swift-tools-version: 5.9
//
// Swift package definition of the iOS part of this plugin.
//
// Used by cordova-ios 8+ (plugin.xml declares <platform name="ios" package="swift">)
// and by Capacitor projects that use Swift Package Manager. Capacitor rewrites the
// cordova-ios dependency below to capacitor-swift-pm when it syncs the plugin.
// CocoaPods based Capacitor projects and cordova-ios 7 ignore this file and use the
// source-file, header-file and framework tags in plugin.xml instead.
//
import PackageDescription

let package = Package(
    name: "cordova-spatialite-storage",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "cordova-spatialite-storage", targets: ["cordova-spatialite-storage"])
    ],
    dependencies: [
        .package(url: "https://github.com/apache/cordova-ios.git", from: "8.0.0")
    ],
    targets: [
        .target(
            name: "cordova-spatialite-storage",
            dependencies: [
                .product(name: "Cordova", package: "cordova-ios"),
                .target(name: "libgeos"),
                .target(name: "libgeos_c"),
                .target(name: "libproj"),
                .target(name: "libspatialite"),
                .target(name: "libsqlite3")
            ],
            path: "src/ios",
            exclude: ["native", "GeneratePluginConfigHeaders.py"],
            sources: ["SQLitePlugin.m"],
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("../common"),
                .headerSearchPath("../common/spatialite"),
                .headerSearchPath("../common/geos")
            ],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedLibrary("iconv"),
                .linkedLibrary("xml2"),
                .linkedLibrary("c++")
            ]
        ),
        // Prebuilt static libraries, see scripts/build-ios-xcframeworks.sh
        .binaryTarget(name: "libgeos", path: "src/ios/native/libgeos.xcframework"),
        .binaryTarget(name: "libgeos_c", path: "src/ios/native/libgeos_c.xcframework"),
        .binaryTarget(name: "libproj", path: "src/ios/native/libproj.xcframework"),
        .binaryTarget(name: "libspatialite", path: "src/ios/native/libspatialite.xcframework"),
        .binaryTarget(name: "libsqlite3", path: "src/ios/native/libsqlite3.xcframework")
    ]
)
