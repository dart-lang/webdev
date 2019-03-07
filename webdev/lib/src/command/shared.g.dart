// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shared.dart';

// **************************************************************************
// CliGenerator
// **************************************************************************

SharedOptions _$parseSharedOptionsResult(ArgResults result) => SharedOptions(
    release: result['release'] as bool,
    verbose: result['verbose'] as bool,
    requireBuildWebCompilers: result['build-web-compilers'] as bool,
    output: result['output'] as String);

ArgParser _$populateSharedOptionsParser(
  ArgParser parser, {
  String outputDefaultOverride,
  bool releaseDefaultOverride,
}) =>
    parser
      ..addOption('output',
          abbr: 'o',
          help:
              'A directory to write the result of a build to. Or a mapping from a top-level directory in the package to the directory to write a filtered build output to. For example "web:deploy".\nA value of "NONE" indicates that no "--output" value should be passed to `build_runner`.',
          defaultsTo: outputDefaultOverride)
      ..addFlag('release',
          abbr: 'r',
          help: 'Build with release mode defaults for builders.',
          defaultsTo: releaseDefaultOverride,
          negatable: true)
      ..addFlag('build-web-compilers',
          help: 'If a dependency on `build_web_compilers` is required to run.',
          defaultsTo: true,
          negatable: true)
      ..addFlag('verbose',
          abbr: 'v',
          help: 'Enables verbose logging.',
          defaultsTo: false,
          negatable: false);

final _$parserForSharedOptions = _$populateSharedOptionsParser(ArgParser());

SharedOptions parseSharedOptions(List<String> args) {
  final result = _$parserForSharedOptions.parse(args);
  return _$parseSharedOptionsResult(result);
}
