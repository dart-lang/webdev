// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert' show jsonDecode;
import 'dart:io';

import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;

/// Note: This script is run from the release script. If you need to run it
/// manually, you can do so with:
///
/// `dart run generate_changelog.dart -p dwds -v X.X.X --reset`
///  - p is the package (either webdev or dwds)
///  - v is the version number
///  -- reset is an optional flag for resetting the CHANGELOG after a release

const _packageOption = 'package';
const _versionOption = 'version';
const _resetFlag = 'reset';

late String? accessToken;

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      _packageOption,
      abbr: 'p',
      allowed: [
        'webdev',
        'dwds',
      ],
    )
    ..addOption(_versionOption, abbr: 'v')
    ..addFlag(_resetFlag, abbr: 'r');

  final argResults = parser.parse(arguments);
  final package = argResults[_packageOption] as String?;
  if (package == null) {
    _logWarning('Please specify package with either -p dwds or -p webdev');
    return;
  }
  final version = argResults[_versionOption] as String?;
  if (version == null) {
    _logWarning('Please specify the version with -v X.X.X');
    return;
  }

  final isReset = argResults[_resetFlag] as bool?;
  if (isReset ?? false) {
    _resetChangelog(
      package: package,
      version: version,
    );
  } else {
    _populateChangelog(
      package: package,
      version: version,
    );
  }
}

void _resetChangelog({
  required String package,
  required String version,
}) {
  _prependLinesToChangelog(
    package,
    lines: [
      '## $version',
      ' - Do not edit, CHANGELOG is populated during the release process.'
    ],
  );
}

void _populateChangelog({
  required String package,
  required String version,
}) async {
  // Populating the CHANGELOG requires calling Github APIs, check if there is an
  // access token for authentication:
  accessToken = await _checkAccessToken();
  if (accessToken == null) {
    _logWarning(
        'No access token found, will call Github APIs without authenticating.');
  }
  _logInfo('Getting latest release name');
  final latestReleaseName = _latestReleaseName(package);
  _logInfo('Looking up commit for $latestReleaseName');
  final commit = await _findCommitMatchingTagName(latestReleaseName);
  _logInfo('Getting all commits since ${commit.sha}');
  final commits = await _getCommitsSince(commit);
  _logInfo('Getting the associated pulls for those commits');
  final pulls = await _getPullsForPackage(
    commits,
    package: package,
  );
  _logInfo('Writing pulls info to CHANGELOG');
  _writePullsToChangelog(
    pulls,
    package: package,
    version: version,
  );
}

void _prependLinesToChangelog(
  String package, {
  required List<String> lines,
}) {
  final changelog = File('../$package/CHANGELOG.md');
  final newLines = [
    ...lines,
    '',
    ...changelog.readAsLinesSync(),
  ];
  final content = newLines.joinWithNewLine();
  return changelog.writeAsStringSync(content);
}

Future<String?> _checkAccessToken() async {
  final tokenFile = File('./gh_access_token.txt');
  final tokenFileExists = await tokenFile.exists();
  if (tokenFileExists) {
    return tokenFile.readAsString();
  }
  return null;
}

String _latestReleaseName(String package) {
  _logInfo('Getting latest release for $package...');
  final changelog = File('../$package/CHANGELOG.md');
  final lines = changelog.readAsLinesSync();
  // The third line contains the latest release in the format "## X.X.X":
  return lines[3].trim().substring(3);
}

Future<_CommitInfo> _findCommitMatchingTagName(String tagMatcher) async {
  final tags =
      _listify(await _githubQuery('tags', params: {'per_page': '100'}));
  final matchingTag = tags.firstWhere((tag) {
    final tagName = tag['name'] as String;
    return tagName.contains(tagMatcher);
  });
  final sha = matchingTag['commit']['sha'] as String;
  final commitInfo = await _githubQuery('commits/$sha');
  final commitDate = commitInfo['commit']['committer']['date'] as String;
  return _CommitInfo(dateStr: commitDate, sha: sha);
}

Future<List<String>> _getCommitsSince(_CommitInfo commit) async {
  final commits = _listify(
      await _githubQuery('commits', params: {'since': commit.dateStr}));
  return commits
      .map((commit) => commit['sha'] as String)
      .where((sha) => sha != commit.sha)
      .toList();
}

Future<List<_PullInfo>> _getPullsForPackage(
  List<String> commits, {
  required String package,
}) async {
  final pullsInfo = <_PullInfo>[];
  for (final commit in commits) {
    final pulls = _listify(await _githubQuery('commits/$commit/pulls'));
    if (pulls.isEmpty) continue;
    final pull = pulls[0];
    final labels = _listify(pull['labels']);
    final isPullForPackage =
        _hasLabelMatching(labels, labelName: 'package:$package');
    if (isPullForPackage) {
      pullsInfo.add(
        _PullInfo(
          number: pull['number'] as int,
          title: pull['title'] as String,
        ),
      );
    }
  }
  return pullsInfo;
}

void _writePullsToChangelog(
  List<_PullInfo> pulls, {
  required String version,
  required String package,
}) {
  final pullInfoLines = pulls.map((pull) {
    final formattedTitle = pull.title.trim().capitalize().addPeriod();
    final pullNumber = pull.number;
    final pullUrl = 'https://github.com/dart-lang/webdev/pull/$pullNumber';
    return '- $formattedTitle - [#$pullNumber]($pullUrl)';
  });
  final changelog = File('../$package/CHANGELOG.md');
  final changelogLines = changelog.readAsLinesSync();
  final newContent = [
    '## $version', // The version header, e.g. "## X.X.X"
    '', // A new line
    ...pullInfoLines,
    '', // Another new line
    ...changelogLines.sublist(3), // Previous versions
  ].joinWithNewLine();
  changelog.writeAsStringSync(newContent);
}

dynamic _githubQuery(String requestPath, {Map<String, dynamic>? params}) async {
  final uri = Uri.https(
    'api.github.com',
    '/repos/dart-lang/webdev/$requestPath',
    params,
  );
  final githubResponse = accessToken == null
      ? await http.get(uri)
      : await http.get(uri, headers: {
          HttpHeaders.authorizationHeader: 'token $accessToken',
        });
  return jsonDecode(githubResponse.body);
}

bool _hasLabelMatching(List<Map<String, dynamic>> labels,
    {required String labelName}) {
  final matchingLabel =
      labels.firstWhereOrNull((label) => label['name'] == labelName);
  return matchingLabel != null;
}

List<Map<String, dynamic>> _listify(dynamic rawJson) {
  try {
    return (rawJson as List).cast<Map<String, dynamic>>();
  } catch (error) {
    _logWarning('Expected JSON list, instead got: $rawJson');
    rethrow;
  }
}

void _logInfo(String message) {
  stdout.writeln(message);
}

void _logWarning(String warning) {
  stderr.writeln(warning);
}

class _PullInfo {
  int number;
  String title;
  _PullInfo({
    required this.number,
    required this.title,
  });
}

class _CommitInfo {
  String dateStr;
  String sha;
  _CommitInfo({
    required this.dateStr,
    required this.sha,
  });
}

extension CapitalizeExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    final firstChar = this[0].toUpperCase();
    final rest = substring(1);
    return '$firstChar$rest';
  }
}

extension PeriodExtension on String {
  String addPeriod() {
    if (isEmpty) return this;
    final lastChar = this[length - 1];
    if (lastChar == '.') return this;
    return '$this.';
  }
}

extension JoinExtension on List<String> {
  String joinWithNewLine() {
    return '${join('\n')}\n';
  }
}
