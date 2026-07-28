// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/loaders/asset_scheme.dart';
import 'package:dwds/src/utilities/web_path_translator.dart';
import 'package:test/test.dart';

void main() {
  group('WebPathTranslator', () {
    group('addLibSegment', () {
      test('adds lib/ to packages paths', () {
        // Checks: packages/foo/bar.dart -> packages/foo/lib/bar.dart
        expect(
          WebPathTranslator.addLibSegment('packages/foo/bar.dart'),
          'packages/foo/lib/bar.dart',
        );
      });

      test('is no-op if lib/ is already present', () {
        // Checks: packages/foo/lib/bar.dart -> packages/foo/lib/bar.dart
        expect(
          WebPathTranslator.addLibSegment('packages/foo/lib/bar.dart'),
          'packages/foo/lib/bar.dart',
        );
      });

      test('is no-op for non-packages paths', () {
        // Checks: web/main.dart -> web/main.dart
        expect(
          WebPathTranslator.addLibSegment('web/main.dart'),
          'web/main.dart',
        );
      });
    });

    group('removeLibSegment', () {
      test('removes lib/ from packages paths', () {
        // Checks: packages/foo/lib/bar.dart -> packages/foo/bar.dart
        expect(
          WebPathTranslator.removeLibSegment('packages/foo/lib/bar.dart'),
          'packages/foo/bar.dart',
        );
      });

      test('is no-op if lib/ is not present', () {
        // Checks: packages/foo/bar.dart -> packages/foo/bar.dart
        expect(
          WebPathTranslator.removeLibSegment('packages/foo/bar.dart'),
          'packages/foo/bar.dart',
        );
      });

      test('is no-op for non-packages paths', () {
        // Checks: web/main.dart -> web/main.dart
        expect(
          WebPathTranslator.removeLibSegment('web/main.dart'),
          'web/main.dart',
        );
      });
    });

    group('translateLibPathToPackagePath', () {
      test('translates lib/ paths to packages/ paths', () {
        // Checks: lib/foo.dart -> packages/my_package/foo.dart
        expect(
          WebPathTranslator.translateLibPathToPackagePath(
            'lib/foo.dart',
            'my_package',
          ),
          'packages/my_package/foo.dart',
        );
      });

      test('translates lib/src/ paths to packages/ paths', () {
        // Checks: lib/src/foo.dart -> packages/my_package/src/foo.dart
        expect(
          WebPathTranslator.translateLibPathToPackagePath(
            'lib/src/foo.dart',
            'my_package',
          ),
          'packages/my_package/src/foo.dart',
        );
      });

      test('is no-op for non-lib paths', () {
        // Checks: web/main.dart -> web/main.dart
        expect(
          WebPathTranslator.translateLibPathToPackagePath(
            'web/main.dart',
            'my_package',
          ),
          'web/main.dart',
        );
      });

      test(
        'throws StateError if rootPackageName is null or empty for lib/ path',
        () {
          // Checks: lib/foo.dart (with null package) -> StateError
          expect(
            () => WebPathTranslator.translateLibPathToPackagePath(
              'lib/foo.dart',
              null,
            ),
            throwsStateError,
          );
          // Checks: lib/foo.dart (with empty package) -> StateError
          expect(
            () => WebPathTranslator.translateLibPathToPackagePath(
              'lib/foo.dart',
              '',
            ),
            throwsStateError,
          );
        },
      );
    });

    group('translateModuleExtension', () {
      test(
        'translates .dart.lib to .ddc (frontendServerOnly to buildRunner)',
        () {
          // Checks: main.dart.lib -> main.ddc
          expect(
            WebPathTranslator.translateModuleExtension(
              'main.dart.lib',
              from: FrontendServerAssetScheme(),
              to: BuildRunnerAssetScheme(),
            ),
            'main.ddc',
          );
          // Checks: main.dart.lib.js -> main.ddc.js
          expect(
            WebPathTranslator.translateModuleExtension(
              'main.dart.lib.js',
              from: FrontendServerAssetScheme(),
              to: BuildRunnerAssetScheme(),
            ),
            'main.ddc.js',
          );
        },
      );

      test(
        'translates .ddc to .dart.lib (buildRunner to frontendServerOnly)',
        () {
          // Checks: main.ddc -> main.dart.lib
          expect(
            WebPathTranslator.translateModuleExtension(
              'main.ddc',
              from: BuildRunnerAssetScheme(),
              to: FrontendServerAssetScheme(),
            ),
            'main.dart.lib',
          );
          // Checks: main.ddc.js -> main.dart.lib.js
          expect(
            WebPathTranslator.translateModuleExtension(
              'main.ddc.js',
              from: BuildRunnerAssetScheme(),
              to: FrontendServerAssetScheme(),
            ),
            'main.dart.lib.js',
          );
        },
      );

      test('is no-op if from and to are the same', () {
        // Checks: main.dart.lib -> main.dart.lib
        expect(
          WebPathTranslator.translateModuleExtension(
            'main.dart.lib',
            from: FrontendServerAssetScheme(),
            to: FrontendServerAssetScheme(),
          ),
          'main.dart.lib',
        );
      });
    });

    group('translateFesToBuildRunnerPath', () {
      test('translates .dart.lib to .ddc', () {
        // Checks: main.dart.lib -> main.ddc
        expect(
          WebPathTranslator.translateFesToBuildRunnerPath('main.dart.lib'),
          'main.ddc',
        );
        // Checks: main.dart.lib.js -> main.ddc.js
        expect(
          WebPathTranslator.translateFesToBuildRunnerPath('main.dart.lib.js'),
          'main.ddc.js',
        );
      });
    });

    group('reconstructAppScheme', () {
      test('is no-op if org-dartlang-app scheme is already present', () {
        // Checks: org-dartlang-app:///web/main.dart -> org-dartlang-app:///web/main.dart
        expect(
          WebPathTranslator.reconstructAppScheme(
            'org-dartlang-app:///web/main.dart',
            '/',
          ),
          'org-dartlang-app:///web/main.dart',
        );
      });

      test('reconstructs scheme for default web dirs', () {
        // Checks: web/main.dart -> org-dartlang-app:///web/main.dart
        expect(
          WebPathTranslator.reconstructAppScheme('web/main.dart', '/'),
          'org-dartlang-app:///web/main.dart',
        );
        // Checks: /test/foo_test.dart -> org-dartlang-app:///test/foo_test.dart
        expect(
          WebPathTranslator.reconstructAppScheme('/test/foo_test.dart', '/'),
          'org-dartlang-app:///test/foo_test.dart',
        );
      });

      test('reconstructs scheme for package paths', () {
        // Checks: /lib/src/library.dart -> org-dartlang-app:///packages/my_package/src/library.dart
        expect(
          WebPathTranslator.reconstructAppScheme(
            '/lib/src/library.dart',
            '/packages/my_package/subdir/main.ddc.js',
          ),
          'org-dartlang-app:///packages/my_package/src/library.dart',
        );
      });

      test('handles package paths without leading slash', () {
        // Checks: lib/src/library.dart -> org-dartlang-app:///packages/my_package/src/library.dart
        expect(
          WebPathTranslator.reconstructAppScheme(
            'lib/src/library.dart',
            '/packages/my_package/subdir/main.ddc.js',
          ),
          'org-dartlang-app:///packages/my_package/src/library.dart',
        );
      });
    });
  });
}
