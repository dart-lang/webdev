// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.9

import 'package:dwds/dwds.dart';
import 'package:dwds/src/debugging/location.dart';
import 'package:dwds/src/debugging/modules.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import 'debugger_test.dart';

void main() {
  globalLoadStrategy = MockLoadStrategy();
  var assetReader = FakeAssetReader();
  var modules = MockModules();

  var locations = Locations(assetReader, modules, '');

  group('JS locations |', () {
    group('location |', () {
      test('is zero based', () async {
        var loc = JsLocation.fromZeroBased('module', 0, 0);
        expect(
            loc,
            isA<JsLocation>()
                .having((l) => l.line, 'line', 0)
                .having((l) => l.column, 'column', 0));
      });

      test('can compare to other location', () async {
        var loc00 = JsLocation.fromZeroBased('module', 0, 0);
        var loc01 = JsLocation.fromZeroBased('module', 0, 1);
        var loc10 = JsLocation.fromZeroBased('module', 1, 0);
        var loc11 = JsLocation.fromZeroBased('module', 1, 1);

        expect(loc00.compareTo(loc01), isNegative);
        expect(loc00.compareTo(loc10), isNegative);
        expect(loc00.compareTo(loc10), isNegative);
        expect(loc00.compareTo(loc11), isNegative);

        expect(loc00.compareTo(loc00), isZero);
        expect(loc11.compareTo(loc00), isPositive);
      });
    });

    group('best location |', () {
      test('does not return location for setup code', () async {
        var jsLocation = await locations.locationForJs('module', 0, 0);
        expect(jsLocation, isNull);
      });

      test('prefers precise match', () async {
        var jsLocation = await locations.locationForJs('module', 37, 0);
        expect(
            jsLocation,
            isA<Location>()
                .having((l) => l.jsLocation.line, 'line', 37)
                .having((l) => l.jsLocation.column, 'column', 0));
      });

      test('matches to location after if stopped in the beginning of the line',
          () async {
        var jsLocation = await locations.locationForJs('module', 39, 4);
        expect(
            jsLocation,
            isA<Location>()
                .having((l) => l.jsLocation.line, 'line', 39)
                .having((l) => l.jsLocation.column, 'column', 6));
      });

      test('matches to location before if stopped in the middle of the line',
          () async {
        var jsLocation = await locations.locationForJs('module', 39, 10);
        expect(
            jsLocation,
            isA<Location>()
                .having((l) => l.jsLocation.line, 'line', 39)
                .having((l) => l.jsLocation.column, 'column', 6));
      });
    });
  });

  group('Dart locations |', () {
    var uri = DartUri('org-dartlang://web/main.dart');

    group('location |', () {
      test('is one based', () async {
        var loc = DartLocation.fromZeroBased(uri, 0, 0);
        expect(
            loc,
            isA<DartLocation>()
                .having((l) => l.line, 'line', 1)
                .having((l) => l.column, 'column', 1));
      });

      test('can compare to other locations', () async {
        var loc00 = DartLocation.fromZeroBased(uri, 0, 0);
        var loc01 = DartLocation.fromZeroBased(uri, 0, 1);
        var loc10 = DartLocation.fromZeroBased(uri, 1, 0);
        var loc11 = DartLocation.fromZeroBased(uri, 1, 1);

        expect(loc00.compareTo(loc01), isNegative);
        expect(loc00.compareTo(loc10), isNegative);
        expect(loc00.compareTo(loc10), isNegative);
        expect(loc00.compareTo(loc11), isNegative);

        expect(loc00.compareTo(loc00), isZero);
        expect(loc11.compareTo(loc00), isPositive);
      });
    });

    group('best location |', () {
      test('does not return location for dart lines not mapped to JS',
          () async {
        var jsLocation = await locations.locationForDart(uri, 0, 0);
        expect(jsLocation, isNull);
      });

      test('returns location after on the same line', () async {
        var jsLocation = await locations.locationForDart(
            DartUri('org-dartlang://web/main.dart'), 11, 0);
        expect(
            jsLocation,
            isA<Location>()
                .having((l) => l.dartLocation.line, 'line', 11)
                .having((l) => l.dartLocation.column, 'column', 3));
      });
    });
  });
}

class MockLoadStrategy implements LoadStrategy {
  @override
  Future<String> bootstrapFor(String entrypoint) async => 'dummy_bootstrap';

  @override
  shelf.Handler get handler =>
      (request) => (request.url.path == 'someDummyPath')
          ? shelf.Response.ok('some dummy response')
          : null;

  @override
  String get id => 'dummy-id';

  @override
  String get moduleFormat => 'dummy-format';

  @override
  String get loadLibrariesModule => '';

  @override
  String get loadLibrariesSnippet => '';

  @override
  String loadLibrarySnippet(String libraryUri) => '';

  @override
  String get loadModuleSnippet => '';

  @override
  ReloadConfiguration get reloadConfiguration => ReloadConfiguration.none;

  @override
  String loadClientSnippet(String clientScript) => 'dummy-load-client-snippet';

  @override
  Future<String> moduleForServerPath(
          String entrypoint, String serverPath) async =>
      'module';

  @override
  Future<String> serverPathForModule(String entrypoint, String module) async =>
      'serverPath';

  @override
  Future<String> sourceMapPathForModule(
          String entrypoint, String module) async =>
      'sourceMapPath';

  @override
  String serverPathForAppUri(String appUri) => 'serverPath';

  @override
  MetadataProvider metadataProviderFor(String entrypoint) => null;

  @override
  void trackEntrypoint(String entrypoint) {}

  @override
  Future<Map<String, ModuleInfo>> moduleInfoForEntrypoint(String entrypoint) =>
      throw UnimplementedError();
}

class MockModules implements Modules {
  @override
  void initialize(String entrypoint) {}

  @override
  Future<Uri> libraryForSource(String serverPath) {
    throw UnimplementedError();
  }

  @override
  Future<String> moduleForSource(String serverPath) async => 'module';

  @override
  Future<Map<String, String>> modules() {
    throw UnimplementedError();
  }

  @override
  Future<String> moduleForlibrary(String libraryUri) {
    throw UnimplementedError();
  }
}
