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
    );

  final argResults = parser.parse(arguments);
  final package = argResults[_packageOption] as String?;
  if (package == null) {
    _logWarning('Please specify package with either -p=dwds or -p=webdev');
    return;
  }

  accessToken = await _checkAccessToken();
  if (accessToken == null) {
    _logWarning(
        'No access token found, will call Github APIs without authenticating.');
  }

  _generateChangelog(
    package: package,
  );
}

Future<String?> _checkAccessToken() async {
  final tokenFile = File('./gh_access_token.txt');
  final tokenFileExists = await tokenFile.exists();
  if (tokenFileExists) {
    return tokenFile.readAsString();
  }
  return null;
}

void _generateChangelog({
  required String package,
}) async {
  _logInfo('Getting latest release for $package...');
  final latestReleaseName = _latestReleaseName(package);
  _logInfo('Looking up commit for $latestReleaseName...');
  final commit = await _findCommitMatchingTagName(latestReleaseName);
  _logInfo('Getting all commits since ${commit.sha}...');
  final commits = await _getCommitsSince(commit);
  _logInfo('Getting the associated pulls for those commits...');
  final pulls = await _getPullsForPackage(commits, package: package);
  _logInfo('Writing pulls info to CHANGELOG...');
  _writePullsToChangelog(pulls, package: package);
}

String _latestReleaseName(String package) {
  final changelog = File('../$package/CHANGELOG.md');
  final lines = changelog.readAsLinesSync();
  // The third line contains the latest release in the format "## XX.X.X":
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
    changelogLines[0], // The version header, e.g. "## XX.X.X"
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
