// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert' show jsonDecode;
import 'dart:io';

import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;

const _packageOption = 'package';

/// Note: Must be run from the /tool directory.
///
/// To generate the CHANGELOG for dwds:
///  `dart run generate_changelog.dart -p dwds`
///
/// To generate the CHANGELOG for WebDev:
///  `dart run generate_changelog.dart -p webdev`

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      _packageOption,
      abbr: 'p',
      allowed: [
        'webdev',
        'dwds',
      ],
    );

  final argResults = parser.parse(arguments);
  final package = argResults[_packageOption] as String?;
  if (package == null) {
    _logWarning('Please specify package with either -p=dwds or -p=webdev');
    return;
  }

  generateChangelog(
    package: package,
  );
  // if (exitCode != 0) {
  //   _logWarning('Run terminated unexpectedly with exit code: $exitCode');
  // }
}

void generateChangelog({
  required String package,
}) async {
  print('Getting latest release for $package...');
  final latestReleaseName = _latestReleaseName(package);
  print('Looking up commit hash for $latestReleaseName...');
  final commitHash = await _findCommitMatchingTagName(latestReleaseName);
  final commits = await _getCommitsSince(commitHash);
  final pulls = await _getPullsForPackage(commits, package: package);
  for (final pull in pulls) {
    print(pull.title);
  }

}

String _latestReleaseName(String package) {
  final changelog = File('../$package/CHANGELOG.md');
  final lines = changelog.readAsLinesSync();
  // The third line contains the last release in the format "## XX.X.X":
  return lines[3].trim().substring(3);
}

Future<String> _findCommitMatchingTagName(String tagMatcher) async {
  final tags = (await _githubQuery('tags', params: {'per_page': '100'}) as List)
      .cast<Map<String, dynamic>>();
  final matchingTag = tags.firstWhere((tag) {
    final tagName = tag['name'] as String;
    return tagName.contains(tagMatcher);
  });
  return matchingTag['commit']['sha'] as String;
}

Future<List<String>> _getCommitsSince(String commitHash) async {
  final commits =
      (await _githubQuery('commits', params: {'since': commitHash}) as List)
          .cast<Map<String, dynamic>>();
  return commits.map((commit) => commit['sha'] as String).toList();
}

Future<List<_PullInfo>> _getPullsForPackage(
  List<String> commits, {
  required String package,
}) async {
  final pullsInfo = <_PullInfo>[];
  for (final commit in commits) {
    final pulls = await _githubQuery('commits/$commit/pulls') as List;
    if (pulls.isEmpty) continue;
    final pull = pulls[0];
    final labels = _listify(pull['labels']);
    final isPullForPackage =
        _hasLabelMatching(labels, labelName: 'package:$package');
    if (isPullForPackage) {
      pullsInfo.add(
        _PullInfo(
          number: pull['number'] as int,
          url: pull['url'] as String,
          title: pull['title'] as String,
        ),
      );
    }
  }
  return pullsInfo;
}

dynamic _githubQuery(String requestPath, {Map<String, dynamic>? params}) async {
  final uri = Uri.https(
    'api.github.com',
    '/repos/dart-lang/webdev/$requestPath',
    params,
  );
  print('requesting $uri');
  final githubResponse = await http.get(uri);
  return jsonDecode(githubResponse.body);
}

bool _hasLabelMatching(List<Map<String, dynamic>> labels,
    {required String labelName}) {
  final matchingLabel =
      labels.firstWhereOrNull((label) => label['name'] == labelName);
  return matchingLabel != null;
}

List<Map<String, dynamic>> _listify(dynamic rawJson) =>
    (rawJson as List).cast<Map<String, dynamic>>();

void _logInfo(String message) {
  stdout.writeln(message);
}

void _logWarning(String warning) {
  stderr.writeln(warning);
}

extension JoinExtension on List<String> {
  String joinWithNewLine() {
    return '${join('\n')}\n';
  }
}

class _PullInfo {
  int number;
  String url;
  String title;
  _PullInfo({
    required this.number,
    required this.url,
    required this.title,
  });
}
