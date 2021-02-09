// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter_devicelab/framework/adb.dart';
import 'package:flutter_devicelab/framework/framework.dart';
import 'package:flutter_devicelab/framework/task_result.dart';
import 'package:flutter_devicelab/framework/utils.dart' as utils;
import 'package:flutter_devicelab/tasks/perf_tests.dart' show ListStatistics;
import 'package:path/path.dart' as path;

const String _bundleName = 'dev.flutter.multipleflutters';
const String _activityName = 'MainActivity';
const int _numberOfIterations = 10;

Future<void> _withApkInstall(
    String apkPath, String bundleName, Function(AndroidDevice) body) async {
  final DeviceDiscovery devices = DeviceDiscovery();
  final AndroidDevice device = await devices.workingDevice as AndroidDevice;
  await device.unlock();
  await device.adb(<String>['install', '-r', apkPath]);
  try {
    await body(device);
  } finally {
    await device.adb(<String>['uninstall', bundleName]);
  }
}

Future<TaskResult> _doTest() async {
  try {
    final String flutterDirectory = utils.flutterDirectory.path;
    final String multipleFluttersPath =
        path.join(flutterDirectory, 'dev', 'benchmarks', 'multiple_flutters');
    final String modulePath = path.join(multipleFluttersPath, 'module');
    final String androidPath = path.join(multipleFluttersPath, 'android');

    final String gradlew = Platform.isWindows ? 'gradlew.bat' : 'gradlew';
    final String gradlewExecutable =
        Platform.isWindows ? '.\\$gradlew' : './$gradlew';
    final String flutterPath = path.join(flutterDirectory, 'bin', 'flutter');
    await utils.eval(flutterPath, <String>['pub', 'get'],
        workingDirectory: modulePath);
    await utils.eval(gradlewExecutable, <String>['assembleRelease'],
        workingDirectory: androidPath);

    final String apkPath = path.join(multipleFluttersPath, 'android', 'app',
        'build', 'outputs', 'apk', 'release', 'app-release.apk');

    TaskResult result;
    await _withApkInstall(apkPath, _bundleName, (AndroidDevice device) async {
      final List<int> totalMemorySamples = <int>[];
      for (int i = 0; i < _numberOfIterations; ++i) {
        await device.adb(<String>[
          'shell',
          'am',
          'start',
          '-n',
          '$_bundleName/$_bundleName.$_activityName'
        ]);
        await Future<void>.delayed(const Duration(seconds: 10));
        final Map<String, dynamic> memoryStats =
            await device.getMemoryStats(_bundleName);
        final int totalMemory = memoryStats['total_kb'] as int;
        totalMemorySamples.add(totalMemory);
        await device.stop(_bundleName);
      }
      final ListStatistics totalMemoryStatistics =
          ListStatistics(totalMemorySamples);

      final Map<String, dynamic> results = <String, dynamic>{
        ...totalMemoryStatistics.asMap('totalMemory')
      };
      result = TaskResult.success(results,
          benchmarkScoreKeys: results.keys.toList());
    });

    return result ?? TaskResult.failure('no results found');
  } catch (ex) {
    return TaskResult.failure(ex.toString());
  }
}

Future<void> main() async {
  task(_doTest);
}
