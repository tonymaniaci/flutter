// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'asset.dart';
import 'base/file_system.dart' show ensureDirectoryExists;
import 'base/process.dart';
import 'dart/package_map.dart';
import 'build_info.dart';
import 'globals.dart';
import 'toolchain.dart';
import 'zip.dart';

const String defaultMainPath = 'lib/main.dart';
const String defaultAssetBasePath = '.';
const String defaultManifestPath = 'flutter.yaml';
String get defaultFlxOutputPath => path.join(getBuildDirectory(), 'app.flx');
String get defaultSnapshotPath => path.join(getBuildDirectory(), 'snapshot_blob.bin');
String get defaultDepfilePath => path.join(getBuildDirectory(), 'snapshot_blob.bin.d');
const String defaultPrivateKeyPath = 'privatekey.der';

const String _kSnapshotKey = 'snapshot_blob.bin';

Future<int> createSnapshot({
  String mainPath,
  String snapshotPath,
  String depfilePath
}) {
  assert(mainPath != null);
  assert(snapshotPath != null);

  final List<String> args = <String>[
    tools.getHostToolPath(HostTool.SkySnapshot),
    '--packages=${path.absolute(PackageMap.globalPackagesPath)}',
    '--snapshot=$snapshotPath'
  ];
  if (depfilePath != null) {
    args.add('--depfile=$depfilePath');
    args.add('--build-output=$snapshotPath');
  }
  args.add(mainPath);
  return runCommandAndStreamOutput(args);
}

/// Build the flx in the build directory and return `localBundlePath` on success.
///
/// Return `null` on failure.
Future<String> buildFlx({
  String mainPath: defaultMainPath,
  bool precompiledSnapshot: false,
  bool includeRobotoFonts: true
}) async {
  int result;
  result = await build(
    snapshotPath: defaultSnapshotPath,
    outputPath: defaultFlxOutputPath,
    mainPath: mainPath,
    precompiledSnapshot: precompiledSnapshot,
    includeRobotoFonts: includeRobotoFonts
  );
  return result == 0 ? defaultFlxOutputPath : null;
}

Future<int> build({
  String mainPath: defaultMainPath,
  String manifestPath: defaultManifestPath,
  String outputPath,
  String snapshotPath,
  String depfilePath,
  String privateKeyPath: defaultPrivateKeyPath,
  String workingDirPath,
  bool precompiledSnapshot: false,
  bool includeRobotoFonts: true,
  bool reportLicensedPackages: false
}) async {
  outputPath ??= defaultFlxOutputPath;
  snapshotPath ??= defaultSnapshotPath;
  depfilePath ??= defaultDepfilePath;
  workingDirPath ??= getAssetBuildDirectory();
  File snapshotFile;

  if (!precompiledSnapshot) {
    ensureDirectoryExists(snapshotPath);

    // In a precompiled snapshot, the instruction buffer contains script
    // content equivalents
    int result = await createSnapshot(
      mainPath: mainPath,
      snapshotPath: snapshotPath,
      depfilePath: depfilePath
    );
    if (result != 0) {
      printError('Failed to run the Flutter compiler. Exit code: $result');
      return result;
    }

    snapshotFile = new File(snapshotPath);
  }

  return assemble(
    manifestPath: manifestPath,
    snapshotFile: snapshotFile,
    outputPath: outputPath,
    privateKeyPath: privateKeyPath,
    workingDirPath: workingDirPath,
    includeRobotoFonts: includeRobotoFonts,
    reportLicensedPackages: reportLicensedPackages
  );
}

Future<int> assemble({
  String manifestPath,
  File snapshotFile,
  String outputPath,
  String privateKeyPath: defaultPrivateKeyPath,
  String workingDirPath,
  bool includeRobotoFonts: true,
  bool reportLicensedPackages: false
}) async {
  outputPath ??= defaultFlxOutputPath;
  workingDirPath ??= getAssetBuildDirectory();
  printTrace('Building $outputPath');

  // Build the asset bundle.
  AssetBundle assetBundle = new AssetBundle();
  int result = await assetBundle.build(
    manifestPath: manifestPath,
    workingDirPath: workingDirPath,
    includeRobotoFonts: includeRobotoFonts,
    reportLicensedPackages: reportLicensedPackages
  );
  if (result != 0) {
    return result;
  }

  ZipBuilder zipBuilder = new ZipBuilder();

  // Add all entries from the asset bundle.
  zipBuilder.entries.addAll(assetBundle.entries);

  if (snapshotFile != null)
    zipBuilder.addEntry(new AssetBundleEntry.fromFile(_kSnapshotKey, snapshotFile));

  ensureDirectoryExists(outputPath);

  printTrace('Encoding zip file to $outputPath');
  zipBuilder.createZip(new File(outputPath), new Directory(workingDirPath));

  printTrace('Built $outputPath.');

  return 0;
}
