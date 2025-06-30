// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

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
    final provider = MetadataProvider(
      'foo.bootstrap.js',
      FakeAssetReader(metadata: _emptySourceMetadata),
    );
    expect(
      await provider.libraries,
      contains('org-dartlang-app:///web/main.dart'),
    );
  });

  test('throws on metadata with absolute import uris', () async {
    final provider = MetadataProvider(
      'foo.bootstrap.js',
      FakeAssetReader(metadata: _fileUriMetadata),
    );
    await expectLater(
      provider.libraries,
      throwsA(const TypeMatcher<AbsoluteImportUriException>()),
    );
  });

  test(
    'module name exists if useModuleName and otherwise use module uri',
    () async {
      final provider = MetadataProvider(
        'foo.bootstrap.js',
        FakeAssetReader(metadata: _emptySourceMetadata),
      );
      final modulePath = 'foo/web/main.ddc.js';
      final moduleName = 'web/main';
      final module = moduleName;
      expect(
        await provider.scriptToModule,
        predicate<Map<String, String>>(
          (scriptToModule) =>
              !scriptToModule.values.any((value) => value == modulePath),
        ),
      );
      expect(await provider.moduleToSourceMap, {
        module: 'foo/web/main.ddc.js.map',
      });
      expect(await provider.modulePathToModule, {modulePath: module});
      expect(await provider.moduleToModulePath, {module: modulePath});
      expect(await provider.modules, {module});
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

  String createMetadataContents(
    Map<String, List<String>> moduleToLibraries,
    Map<String, List<String>> libraryToParts,
  ) {
    final contents = StringBuffer('');
    for (final module in moduleToLibraries.keys) {
      final moduleMetadata = ModuleMetadata(
        module,
        'load__web__$module',
        'foo/web/$module.ddc.js.map',
        'foo/web/$module.ddc.js',
      );
      for (final library in moduleToLibraries[module]!) {
        moduleMetadata.addLibrary(
          LibraryMetadata(library, library, libraryToParts[library] ?? []),
        );
      }
      contents.writeln(json.encode(moduleMetadata.toJson()));
    }
    contents.write('// intentionally empty: ...');
    return contents.toString();
  }

  Future<void> verifyExpectations(
    MetadataProvider provider,
    Map<String, List<String>> moduleToLibraries,
    Map<String, List<String>> libraryToParts,
  ) async {
    final scriptToModule = await provider.scriptToModule;
    final expectedScriptToModule = <String, String>{};
    for (final module in moduleToLibraries.keys) {
      final libraries = moduleToLibraries[module]!;
      for (final library in libraries) {
        expectedScriptToModule[library] = module;
        final parts = libraryToParts[library];
        if (parts != null) {
          for (final part in parts) {
            expectedScriptToModule[part] = module;
          }
        }
      }
    }
    for (final entry in expectedScriptToModule.entries) {
      expect(scriptToModule[entry.key], entry.value);
    }

    final moduleToSourceMap = await provider.moduleToSourceMap;
    final expectedModuleToSourceMap = moduleToLibraries.keys.fold(
      <String, String>{},
      (map, module) {
        map[module] = 'foo/web/$module.ddc.js.map';
        return map;
      },
    );
    for (final entry in expectedModuleToSourceMap.entries) {
      expect(moduleToSourceMap[entry.key], entry.value);
    }

    final modulePathToModule = await provider.modulePathToModule;
    final expectedModulePathToModule = moduleToLibraries.keys.fold(
      <String, String>{},
      (map, module) {
        map['foo/web/$module.ddc.js'] = module;
        return map;
      },
    );
    for (final entry in expectedModulePathToModule.entries) {
      expect(modulePathToModule[entry.key], entry.value);
    }

    expect(await provider.modules, containsAll(moduleToLibraries.keys));
  }

  test('reinitialize produces correct report', () async {
    final moduleToLibraries = <String, List<String>>{
      'm1': [
        'org-dartlang-app:///web/l1.dart',
        'org-dartlang-app:///web/l2.dart',
      ],
      'm2': [
        'org-dartlang-app:///web/l3.dart',
        'org-dartlang-app:///web/l4.dart',
      ],
      'm3': [
        'org-dartlang-app:///web/l5.dart',
        'org-dartlang-app:///web/l6.dart',
      ],
    };
    final libraryToParts = <String, List<String>>{
      'l1': ['org-dartlang-app:///web/l1_p1.dart'],
    };
    final assetReader = FakeAssetReader(
      metadata: createMetadataContents(moduleToLibraries, libraryToParts),
    );
    final provider = MetadataProvider('foo.bootstrap.js', assetReader);
    await verifyExpectations(provider, moduleToLibraries, libraryToParts);

    final newModuleToLibraries = <String, List<String>>{
      'm1': [
        'org-dartlang-app:///web/l1.dart',
        'org-dartlang-app:///web/l2.dart',
      ],
      'm3': ['org-dartlang-app:///web/l3.dart'],
      'm4': [
        'org-dartlang-app:///web/l4.dart',
        'org-dartlang-app:///web/l7.dart',
      ],
    };
    final newLibraryToParts = <String, List<String>>{
      'l1': ['org-dartlang-app:///web/l1_p1.dart'],
      'l7': ['org-dartlang-app:///web/l7_p1.dart'],
    };
    final reloadedModulesToLibraries = <String, List<String>>{
      'm3': ['org-dartlang-app:///web/l3.dart'],
      'm4': [
        'org-dartlang-app:///web/l4.dart',
        'org-dartlang-app:///web/l7.dart',
      ],
    };
    assetReader.metadata = createMetadataContents(
      newModuleToLibraries,
      newLibraryToParts,
    );
    final invalidatedModuleReport = await provider.reinitializeAfterReload(
      reloadedModulesToLibraries,
    );
    expect(invalidatedModuleReport.deletedModules, ['m2']);
    expect(invalidatedModuleReport.deletedLibraries, [
      'org-dartlang-app:///web/l5.dart',
      'org-dartlang-app:///web/l6.dart',
    ]);
    expect(
      invalidatedModuleReport.reloadedModules,
      reloadedModulesToLibraries.keys,
    );
    expect(
      invalidatedModuleReport.reloadedLibraries,
      containsAll(
        reloadedModulesToLibraries.values.fold<List<String>>([], (value, l) {
          value.addAll(l);
          return l;
        }),
      ),
    );
    await verifyExpectations(provider, newModuleToLibraries, newLibraryToParts);
  });
}
