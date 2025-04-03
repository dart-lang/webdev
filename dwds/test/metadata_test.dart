// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))
library;

import 'package:dwds/src/debugging/metadata/module_metadata.dart';
import 'package:dwds/src/debugging/metadata/provider.dart';
import 'package:test/test.dart';

import 'fixtures/fakes.dart';
import 'fixtures/utilities.dart';

const _emptySourceMetadata =
    '{"version":"1.0.0","name":"web/main","closureName":"load__web__main",'
    '"sourceMapUri":"foo/web/main.ddc.js.map",'
    '"moduleUri":"foo/web/main.ddc.js",'
    '"libraries":[{"name":"main",'
    '"importUri":"org-dartlang-app:///web/main.dart",'
    '"fileUri":"org-dartlang-app:///web/main.dart","partUris":[]}]}\n'
    '// intentionally empty: package blah has no dart sources';

const _fileUriMetadata =
    '{"version":"1.0.0","name":"web/main","closureName":"load__web__main",'
    '"sourceMapUri":"foo/web/main.ddc.js.map",'
    '"moduleUri":"foo/web/main.ddc.js",'
    '"libraries":[{"name":"main",'
    '"importUri":"file:/Users/foo/blah/sample/lib/bar.dart",'
    '"fileUri":"org-dartlang-app:///web/main.dart","partUris":[]}]}\n'
    '// intentionally empty: package blah has no dart sources';

void main() {
  final toolConfiguration = TestToolConfiguration.withLoadStrategy(
    loadStrategy: FakeStrategy(FakeAssetReader()),
  );
  setGlobalsForTesting(toolConfiguration: toolConfiguration);
  test('can parse metadata with empty sources', () async {
    for (final useModuleName in [true, false]) {
      final provider = MetadataProvider(
        'foo.bootstrap.js',
        FakeAssetReader(metadata: _emptySourceMetadata),
        useModuleName: useModuleName,
      );
      expect(
        await provider.libraries,
        contains('org-dartlang-app:///web/main.dart'),
      );
    }
  });

  test('throws on metadata with absolute import uris', () async {
    for (final useModuleName in [true, false]) {
      final provider = MetadataProvider(
        'foo.bootstrap.js',
        FakeAssetReader(metadata: _fileUriMetadata),
        useModuleName: useModuleName,
      );
      await expectLater(
        provider.libraries,
        throwsA(const TypeMatcher<AbsoluteImportUriException>()),
      );
    }
  });

  test(
    'module name exists if useModuleName and otherwise use module uri',
    () async {
      for (final useModuleName in [true, false]) {
        final provider = MetadataProvider(
          'foo.bootstrap.js',
          FakeAssetReader(metadata: _emptySourceMetadata),
          useModuleName: useModuleName,
        );
        final modulePath = 'foo/web/main.ddc.js';
        final moduleName = 'web/main';
        final module = useModuleName ? moduleName : modulePath;
        expect(
          await provider.scriptToModule,
          predicate<Map<String, String>>(
            (scriptToModule) =>
                !scriptToModule.values.any(
                  (value) => value == (useModuleName ? modulePath : moduleName),
                ),
          ),
        );
        expect(await provider.moduleToSourceMap, {
          module: 'foo/web/main.ddc.js.map',
        });
        expect(await provider.modulePathToModule, {modulePath: module});
        expect(await provider.moduleToModulePath, {module: modulePath});
        expect(await provider.modules, {module});
      }
    },
  );

  test('creates metadata from json', () async {
    const json = {
      'version': '1.0.0',
      'name': 'web/main',
      'closureName': 'load__web__main',
      'sourceMapUri': 'foo/web/main.ddc.js.map',
      'moduleUri': 'foo/web/main.ddc.js',
      'libraries': [
        {
          'name': 'main',
          'importUri': 'org-dartlang-app:///web/main.dart',
          'partUris': ['org-dartlang-app:///web/main.dart'],
        },
      ],
    };

    final metadata = ModuleMetadata.fromJson(json);
    expect(metadata.version, '1.0.0');
    expect(metadata.name, 'web/main');
    expect(metadata.closureName, 'load__web__main');
    expect(metadata.sourceMapUri, 'foo/web/main.ddc.js.map');
    expect(metadata.moduleUri, 'foo/web/main.ddc.js');
    final libraries = metadata.libraries;
    expect(libraries.length, 1);
    for (final lib in libraries.values) {
      expect(lib.name, 'main');
      expect(lib.importUri, 'org-dartlang-app:///web/main.dart');
      final parts = lib.partUris;
      expect(parts.length, 1);
      expect(parts[0], 'org-dartlang-app:///web/main.dart');
    }
  });
}
