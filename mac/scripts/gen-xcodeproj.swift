#!/usr/bin/env swift
//
// gen-xcodeproj.swift — Walks the `McController/` source tree and emits
// a fresh `McController.xcodeproj/project.pbxproj` for a single macOS
// app target. Re-run whenever a file is added or removed.
//
// Why generate? Hand-edited `project.pbxproj` files are brittle —
// missing a file ref or a build-file pair turns into "Build input
// missing" errors that Xcode reports far from the cause. A regenerator
// lets us keep the source tree as the single source of truth.

import Foundation

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let scriptDir = scriptURL.deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()
let sourceRoot = projectRoot.appendingPathComponent("McController")
let projectName = "McController"
let xcodeprojDir = projectRoot.appendingPathComponent("\(projectName).xcodeproj")
let pbxprojPath = xcodeprojDir.appendingPathComponent("project.pbxproj")

try FileManager.default.createDirectory(at: xcodeprojDir, withIntermediateDirectories: true)

// MARK: - File discovery

struct SourceFile {
    let url: URL
    /// Relative path from the project root used as `path` in
    /// PBXFileReference (groups handle the nesting).
    let relPath: String
    let isSource: Bool
    let isResource: Bool
}

func walk(_ dir: URL) -> [URL] {
    var out: [URL] = []
    let fm = FileManager.default
    guard let it = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey])
    else { return [] }
    for case let url as URL in it {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        if values?.isRegularFile == true {
            // Skip macOS junk + asset catalog internals (we reference the
            // whole `.xcassets` bundle once, not its contents).
            let last = url.lastPathComponent
            if last.hasPrefix(".") { continue }
            // Don't pull contents of .xcassets into the source list — the
            // asset catalog bundle itself becomes one resource entry.
            if url.path.contains(".xcassets/") { continue }
            out.append(url)
        }
    }
    return out
}

var swiftFiles: [SourceFile] = []
var resourceFiles: [SourceFile] = []
let allUrls = walk(sourceRoot)

for url in allUrls {
    let rel = url.path.replacingOccurrences(
        of: projectRoot.path + "/", with: "")
    let ext = url.pathExtension.lowercased()
    if ext == "swift" {
        swiftFiles.append(SourceFile(url: url, relPath: rel, isSource: true, isResource: false))
    }
    // Resources we want copied: assets, plist isn't a resource.
}

// Asset catalog as a single resource reference.
let assetsURL = sourceRoot.appendingPathComponent("Resources/Assets.xcassets")
if FileManager.default.fileExists(atPath: assetsURL.path) {
    resourceFiles.append(SourceFile(
        url: assetsURL,
        relPath: "McController/Resources/Assets.xcassets",
        isSource: false,
        isResource: true))
}

// Sort for stability.
swiftFiles.sort { $0.relPath < $1.relPath }

// MARK: - UUID allocator
//
// Xcode IDs are 24-character uppercase hex. We just need uniqueness +
// stability across regenerations, so we hash the (kind, key) pair into
// a 24-char hex prefix derived from MD5. Stable IDs help Xcode merge
// future regenerations without flagging unrelated diffs.

import CryptoKit

func idFor(_ kind: String, _ key: String) -> String {
    let raw = "\(kind):\(key)"
    let digest = Insecure.MD5.hash(data: Data(raw.utf8))
    let hex = digest.map { String(format: "%02X", $0) }.joined()
    return String(hex.prefix(24))
}

// MARK: - Pbxproj emission

var lines: [String] = []
func L(_ s: String) { lines.append(s) }

L("// !$*UTF8*$!")
L("{")
L("\tarchiveVersion = 1;")
L("\tclasses = {")
L("\t};")
L("\tobjectVersion = 56;")
L("\tobjects = {")
L("")

// --- PBXBuildFile (one per source + each resource)

L("/* Begin PBXBuildFile section */")
for f in swiftFiles {
    let fileRefID = idFor("file-ref", f.relPath)
    let buildID = idFor("build-file", f.relPath)
    L("\t\(buildID) /* \(f.url.lastPathComponent) in Sources */ = {isa = PBXBuildFile; fileRef = \(fileRefID) /* \(f.url.lastPathComponent) */; };")
}
for f in resourceFiles {
    let fileRefID = idFor("file-ref", f.relPath)
    let buildID = idFor("build-file", f.relPath)
    L("\t\(buildID) /* \(f.url.lastPathComponent) in Resources */ = {isa = PBXBuildFile; fileRef = \(fileRefID) /* \(f.url.lastPathComponent) */; };")
}
L("/* End PBXBuildFile section */")
L("")

// --- PBXFileReference

L("/* Begin PBXFileReference section */")

// App product
let productID = idFor("product", "McController.app")
L("\t\(productID) /* McController.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = McController.app; sourceTree = BUILT_PRODUCTS_DIR; };")

// Info.plist
let infoPlistID = idFor("file-ref", "McController/Resources/Info.plist")
L("\t\(infoPlistID) /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; };")

// entitlements
let entitlementsID = idFor("file-ref", "McController/Resources/McController.entitlements")
L("\t\(entitlementsID) /* McController.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = McController.entitlements; sourceTree = \"<group>\"; };")

for f in swiftFiles {
    let id = idFor("file-ref", f.relPath)
    let name = f.url.lastPathComponent
    L("\t\(id) /* \(name) */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \(name); sourceTree = \"<group>\"; };")
}
for f in resourceFiles {
    let id = idFor("file-ref", f.relPath)
    let name = f.url.lastPathComponent
    let isAsset = name.hasSuffix(".xcassets")
    let fileType = isAsset ? "folder.assetcatalog" : "file"
    L("\t\(id) /* \(name) */ = {isa = PBXFileReference; lastKnownFileType = \(fileType); path = \(name); sourceTree = \"<group>\"; };")
}
L("/* End PBXFileReference section */")
L("")

// --- PBXGroup (build the folder hierarchy from relPaths)

/// Tree node mirroring the folder layout, used to emit nested PBXGroups.
class GroupNode {
    let name: String
    let path: String  // relative to parent
    var children: [String: GroupNode] = [:]
    var files: [String] = []  // relPath strings
    init(name: String, path: String) { self.name = name; self.path = path }
}

let root = GroupNode(name: "McController", path: "McController")

for f in swiftFiles + resourceFiles {
    let parts = f.relPath.split(separator: "/").map(String.init)
    // parts[0] is "McController" — drop, then walk the rest minus the file.
    let dirParts = Array(parts.dropFirst().dropLast())
    var cur = root
    for d in dirParts {
        if let next = cur.children[d] { cur = next; continue }
        let node = GroupNode(name: d, path: d)
        cur.children[d] = node
        cur = node
    }
    cur.files.append(f.relPath)
}

// Resources/Info.plist + Resources/McController.entitlements are not
// "source files" — we register them as PBXFileReference but treat
// Resources directory as the parent group. Path-wise they're already
// under McController/Resources so they nest correctly.
let resourcesGroup = root.children["Resources"] ?? GroupNode(name: "Resources", path: "Resources")
root.children["Resources"] = resourcesGroup
// Add Info.plist + entitlements file refs via synthetic relPaths.
resourcesGroup.files.append("McController/Resources/Info.plist")
resourcesGroup.files.append("McController/Resources/McController.entitlements")
// And the asset catalog if it was discovered.
if let assets = resourceFiles.first(where: { $0.url.lastPathComponent.hasSuffix(".xcassets") }) {
    if !resourcesGroup.files.contains(assets.relPath) {
        resourcesGroup.files.append(assets.relPath)
    }
}

L("/* Begin PBXGroup section */")

// Root group
let rootGroupID = idFor("group", "<root>")
let productsGroupID = idFor("group", "Products")
let mcControllerGroupID = idFor("group", "McController")
L("\t\(rootGroupID) = {")
L("\t\tisa = PBXGroup;")
L("\t\tchildren = (")
L("\t\t\t\(mcControllerGroupID) /* McController */,")
L("\t\t\t\(productsGroupID) /* Products */,")
L("\t\t);")
L("\t\tsourceTree = \"<group>\";")
L("\t};")

L("\t\(productsGroupID) /* Products */ = {")
L("\t\tisa = PBXGroup;")
L("\t\tchildren = (")
L("\t\t\t\(productID) /* McController.app */,")
L("\t\t);")
L("\t\tname = Products;")
L("\t\tsourceTree = \"<group>\";")
L("\t};")

func emitGroup(_ node: GroupNode, parentRelPath: String) -> String {
    let myPath = parentRelPath.isEmpty ? node.path : parentRelPath + "/" + node.path
    let id = idFor("group", myPath)
    // Recurse children first to collect their IDs.
    let sortedChildren = node.children.values.sorted { $0.name < $1.name }
    let childIDs = sortedChildren.map { emitGroup($0, parentRelPath: myPath) }
    L("\t\(id) /* \(node.name) */ = {")
    L("\t\tisa = PBXGroup;")
    L("\t\tchildren = (")
    for (childIdx, c) in sortedChildren.enumerated() {
        L("\t\t\t\(childIDs[childIdx]) /* \(c.name) */,")
    }
    let sortedFiles = node.files.sorted()
    for f in sortedFiles {
        let name = (f as NSString).lastPathComponent
        L("\t\t\t\(idFor("file-ref", f)) /* \(name) */,")
    }
    L("\t\t);")
    L("\t\tpath = \(node.path);")
    L("\t\tsourceTree = \"<group>\";")
    L("\t};")
    return id
}

// We need the McController group ID to match what we used above.
// The recursive emit returns the same ID since we hash by path —
// just call it and ignore the return.
_ = emitGroup(root, parentRelPath: "")

L("/* End PBXGroup section */")
L("")

// --- Build phases

let sourcesPhaseID = idFor("phase", "Sources")
let resourcesPhaseID = idFor("phase", "Resources")
let frameworksPhaseID = idFor("phase", "Frameworks")

L("/* Begin PBXSourcesBuildPhase section */")
L("\t\(sourcesPhaseID) /* Sources */ = {")
L("\t\tisa = PBXSourcesBuildPhase;")
L("\t\tbuildActionMask = 2147483647;")
L("\t\tfiles = (")
for f in swiftFiles {
    let buildID = idFor("build-file", f.relPath)
    L("\t\t\t\(buildID) /* \(f.url.lastPathComponent) in Sources */,")
}
L("\t\t);")
L("\t\trunOnlyForDeploymentPostprocessing = 0;")
L("\t};")
L("/* End PBXSourcesBuildPhase section */")
L("")

L("/* Begin PBXResourcesBuildPhase section */")
L("\t\(resourcesPhaseID) /* Resources */ = {")
L("\t\tisa = PBXResourcesBuildPhase;")
L("\t\tbuildActionMask = 2147483647;")
L("\t\tfiles = (")
for f in resourceFiles {
    let buildID = idFor("build-file", f.relPath)
    L("\t\t\t\(buildID) /* \(f.url.lastPathComponent) in Resources */,")
}
L("\t\t);")
L("\t\trunOnlyForDeploymentPostprocessing = 0;")
L("\t};")
L("/* End PBXResourcesBuildPhase section */")
L("")

L("/* Begin PBXFrameworksBuildPhase section */")
L("\t\(frameworksPhaseID) /* Frameworks */ = {")
L("\t\tisa = PBXFrameworksBuildPhase;")
L("\t\tbuildActionMask = 2147483647;")
L("\t\tfiles = (")
L("\t\t);")
L("\t\trunOnlyForDeploymentPostprocessing = 0;")
L("\t};")
L("/* End PBXFrameworksBuildPhase section */")
L("")

// --- Target

let targetID = idFor("target", "McController")
let targetConfigListID = idFor("config-list", "target:McController")
let projectConfigListID = idFor("config-list", "project")
let debugConfigID = idFor("config", "Debug:McController")
let releaseConfigID = idFor("config", "Release:McController")
let projectDebugConfigID = idFor("config", "Debug:Project")
let projectReleaseConfigID = idFor("config", "Release:Project")

L("/* Begin PBXNativeTarget section */")
L("\t\(targetID) /* McController */ = {")
L("\t\tisa = PBXNativeTarget;")
L("\t\tbuildConfigurationList = \(targetConfigListID) /* Build configuration list for PBXNativeTarget \"McController\" */;")
L("\t\tbuildPhases = (")
L("\t\t\t\(sourcesPhaseID) /* Sources */,")
L("\t\t\t\(frameworksPhaseID) /* Frameworks */,")
L("\t\t\t\(resourcesPhaseID) /* Resources */,")
L("\t\t);")
L("\t\tbuildRules = (")
L("\t\t);")
L("\t\tdependencies = (")
L("\t\t);")
L("\t\tname = McController;")
L("\t\tproductName = McController;")
L("\t\tproductReference = \(productID) /* McController.app */;")
L("\t\tproductType = \"com.apple.product-type.application\";")
L("\t};")
L("/* End PBXNativeTarget section */")
L("")

// --- Project

let projectID = idFor("project", "root")

L("/* Begin PBXProject section */")
L("\t\(projectID) /* Project object */ = {")
L("\t\tisa = PBXProject;")
L("\t\tattributes = {")
L("\t\t\tBuildIndependentTargetsInParallel = YES;")
L("\t\t\tLastSwiftUpdateCheck = 1600;")
L("\t\t\tLastUpgradeCheck = 1600;")
L("\t\t\tTargetAttributes = {")
L("\t\t\t\t\(targetID) = {")
L("\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
L("\t\t\t\t};")
L("\t\t\t};")
L("\t\t};")
L("\t\tbuildConfigurationList = \(projectConfigListID) /* Build configuration list for PBXProject \"McController\" */;")
L("\t\tcompatibilityVersion = \"Xcode 14.0\";")
L("\t\tdevelopmentRegion = en;")
L("\t\thasScannedForEncodings = 0;")
L("\t\tknownRegions = (")
L("\t\t\ten,")
L("\t\t\t\"zh-Hans\",")
L("\t\t\tBase,")
L("\t\t);")
L("\t\tmainGroup = \(rootGroupID);")
L("\t\tproductRefGroup = \(productsGroupID) /* Products */;")
L("\t\tprojectDirPath = \"\";")
L("\t\tprojectRoot = \"\";")
L("\t\ttargets = (")
L("\t\t\t\(targetID) /* McController */,")
L("\t\t);")
L("\t};")
L("/* End PBXProject section */")
L("")

// --- Build configurations

L("/* Begin XCBuildConfiguration section */")

// Project-wide Debug
L("\t\(projectDebugConfigID) /* Debug */ = {")
L("\t\tisa = XCBuildConfiguration;")
L("\t\tbuildSettings = {")
L("\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
L("\t\t\tCLANG_ANALYZER_NONNULL = YES;")
L("\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;")
L("\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
L("\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;")
L("\t\t\tCOPY_PHASE_STRIP = NO;")
L("\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;")
L("\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
L("\t\t\tENABLE_TESTABILITY = YES;")
L("\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;")
L("\t\t\tGCC_DYNAMIC_NO_PIC = NO;")
L("\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
L("\t\t\tGCC_OPTIMIZATION_LEVEL = 0;")
L("\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (")
L("\t\t\t\t\"DEBUG=1\",")
L("\t\t\t\t\"$(inherited)\",")
L("\t\t\t);")
L("\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
L("\t\t\tONLY_ACTIVE_ARCH = YES;")
L("\t\t\tSDKROOT = macosx;")
L("\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
L("\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
L("\t\t};")
L("\t\tname = Debug;")
L("\t};")

// Project-wide Release
L("\t\(projectReleaseConfigID) /* Release */ = {")
L("\t\tisa = XCBuildConfiguration;")
L("\t\tbuildSettings = {")
L("\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
L("\t\t\tCLANG_ANALYZER_NONNULL = YES;")
L("\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;")
L("\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
L("\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;")
L("\t\t\tCOPY_PHASE_STRIP = NO;")
L("\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";")
L("\t\t\tENABLE_NS_ASSERTIONS = NO;")
L("\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
L("\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;")
L("\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
L("\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
L("\t\t\tSDKROOT = macosx;")
L("\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
L("\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";")
L("\t\t};")
L("\t\tname = Release;")
L("\t};")

// Target Debug
L("\t\(debugConfigID) /* Debug */ = {")
L("\t\tisa = XCBuildConfiguration;")
L("\t\tbuildSettings = {")
L("\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
L("\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
L("\t\t\tCODE_SIGN_ENTITLEMENTS = McController/Resources/McController.entitlements;")
L("\t\t\tCODE_SIGN_STYLE = Automatic;")
L("\t\t\tCODE_SIGN_IDENTITY = \"-\";")
L("\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
L("\t\t\tCURRENT_PROJECT_VERSION = 1;")
L("\t\t\tENABLE_HARDENED_RUNTIME = YES;")
L("\t\t\tGENERATE_INFOPLIST_FILE = NO;")
L("\t\t\tINFOPLIST_FILE = McController/Resources/Info.plist;")
L("\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = \"© Linloir\";")
L("\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
L("\t\t\t\t\"$(inherited)\",")
L("\t\t\t\t\"@executable_path/../Frameworks\",")
L("\t\t\t);")
L("\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
L("\t\t\tMARKETING_VERSION = 1.0.1;")
L("\t\t\tPRODUCT_BUNDLE_IDENTIFIER = cn.linloir.couchmc.mac;")
L("\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
L("\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
L("\t\t\tSWIFT_VERSION = 5.0;")
L("\t\t};")
L("\t\tname = Debug;")
L("\t};")

// Target Release
L("\t\(releaseConfigID) /* Release */ = {")
L("\t\tisa = XCBuildConfiguration;")
L("\t\tbuildSettings = {")
L("\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
L("\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
L("\t\t\tCODE_SIGN_ENTITLEMENTS = McController/Resources/McController.entitlements;")
L("\t\t\tCODE_SIGN_STYLE = Automatic;")
L("\t\t\tCODE_SIGN_IDENTITY = \"-\";")
L("\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
L("\t\t\tCURRENT_PROJECT_VERSION = 1;")
L("\t\t\tENABLE_HARDENED_RUNTIME = YES;")
L("\t\t\tGENERATE_INFOPLIST_FILE = NO;")
L("\t\t\tINFOPLIST_FILE = McController/Resources/Info.plist;")
L("\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = \"© Linloir\";")
L("\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
L("\t\t\t\t\"$(inherited)\",")
L("\t\t\t\t\"@executable_path/../Frameworks\",")
L("\t\t\t);")
L("\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
L("\t\t\tMARKETING_VERSION = 1.0.1;")
L("\t\t\tPRODUCT_BUNDLE_IDENTIFIER = cn.linloir.couchmc.mac;")
L("\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
L("\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
L("\t\t\tSWIFT_VERSION = 5.0;")
L("\t\t};")
L("\t\tname = Release;")
L("\t};")

L("/* End XCBuildConfiguration section */")
L("")

// Build configuration lists
L("/* Begin XCConfigurationList section */")
L("\t\(projectConfigListID) /* Build configuration list for PBXProject \"McController\" */ = {")
L("\t\tisa = XCConfigurationList;")
L("\t\tbuildConfigurations = (")
L("\t\t\t\(projectDebugConfigID) /* Debug */,")
L("\t\t\t\(projectReleaseConfigID) /* Release */,")
L("\t\t);")
L("\t\tdefaultConfigurationIsVisible = 0;")
L("\t\tdefaultConfigurationName = Release;")
L("\t};")
L("\t\(targetConfigListID) /* Build configuration list for PBXNativeTarget \"McController\" */ = {")
L("\t\tisa = XCConfigurationList;")
L("\t\tbuildConfigurations = (")
L("\t\t\t\(debugConfigID) /* Debug */,")
L("\t\t\t\(releaseConfigID) /* Release */,")
L("\t\t);")
L("\t\tdefaultConfigurationIsVisible = 0;")
L("\t\tdefaultConfigurationName = Release;")
L("\t};")
L("/* End XCConfigurationList section */")

L("\t};")
L("\trootObject = \(projectID) /* Project object */;")
L("}")

let output = lines.joined(separator: "\n") + "\n"
try output.write(to: pbxprojPath, atomically: true, encoding: .utf8)

print("✅ Generated \(pbxprojPath.path)")
print("   Source files: \(swiftFiles.count)")
print("   Resources:    \(resourceFiles.count)")
