// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

@Retry(0)

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:webdev/src/serve/utils.dart';

void main() {
  Directory from;
  Directory to;

  setUp(() {
    from = Directory.systemTemp.createTempSync('from');
    to = Directory.systemTemp.createTempSync('to');
  });

  tearDown(() {
    from?.deleteSync(recursive: true);
    to?.deleteSync(recursive: true);
  });

  test('updatePath does nothing for non-existing directories', () async {
    var subDirFrom = Directory(p.join(from.path, '1'));
    var subDirTo = Directory(p.join(to.path, '2'));

    expect(subDirFrom.existsSync(), isFalse);
    expect(subDirTo.existsSync(), isFalse);

    await updatePath(subDirFrom.path, subDirTo.path);

    expect(subDirFrom.existsSync(), isFalse);
    expect(subDirTo.existsSync(), isFalse);
  });

  test('updatePath creates non-existing directories', () async {
    var subDirFrom = Directory(p.join(from.path, '1'));
    var subDirTo = Directory(p.join(to.path, '2'));

    subDirFrom.createSync();

    expect(subDirFrom.existsSync(), isTrue);
    expect(subDirTo.existsSync(), isFalse);

    await updatePath(subDirFrom.path, subDirTo.path);

    expect(subDirFrom.existsSync(), isTrue);
    expect(subDirTo.existsSync(), isTrue);
  });

  test('updatePath removes stale directories', () async {
    var subDirFrom = Directory(p.join(from.path, '1'));
    var subDirTo = Directory(p.join(to.path, '2'));

    subDirTo.createSync();

    expect(subDirFrom.existsSync(), isFalse);
    expect(subDirTo.existsSync(), isTrue);

    await updatePath(from.path, to.path);

    expect(subDirFrom.existsSync(), isFalse);
    expect(subDirTo.existsSync(), isFalse);
  });

  test('updatePath updates directories', () async {
    var subDirFrom = Directory(p.join(from.path, '1'));
    var subDirTo = Directory(p.join(to.path, '2'));

    subDirFrom.createSync();
    subDirTo.createSync();

    var listFrom =
        from.listSync().map((e) => p.relative(e.path, from: from.path));
    await updatePath(from.path, to.path);

    var listTo = to.listSync().map((e) => p.relative(e.path, from: to.path));
    expect(listFrom, listTo);
  });

  test('updatePath updates files', () async {
    var fileFrom = File(p.join(from.path, '1'));
    var fileTo = File(p.join(to.path, '2'));

    fileFrom.createSync();
    fileTo.createSync();

    var listFrom =
        from.listSync().map((e) => p.relative(e.path, from: from.path));
    await updatePath(from.path, to.path);

    var listTo = to.listSync().map((e) => p.relative(e.path, from: to.path));
    expect(listFrom, listTo);
  });

  test('updatePath updates files and directories', () async {
    var subDirFrom = Directory(p.join(from.path, '1'));
    var subDirTo1 = Directory(p.join(to.path, '1'));
    var subDirTo2 = Directory(p.join(to.path, '2'));

    subDirFrom.createSync();
    subDirTo1.createSync();
    subDirTo2.createSync();

    var fileFrom = File(p.join(subDirFrom.path, 'a'));
    var fileTo1 = File(p.join(subDirTo1.path, 'b'));
    var fileTo2 = File(p.join(subDirTo2.path, 'b'));

    fileFrom.createSync();
    fileTo1.createSync();
    fileTo2.createSync();

    var listFrom = from
        .listSync(recursive: true)
        .map((e) => p.relative(e.path, from: from.path));
    await updatePath(from.path, to.path);

    var listTo = to
        .listSync(recursive: true)
        .map((e) => p.relative(e.path, from: to.path));
    expect(listFrom, listTo);
  });

  test('updatePath updates stale files', () async {
    var fileFrom = File(p.join(from.path, '1'));
    var fileTo = File(p.join(to.path, '1'));

    fileTo.writeAsStringSync('contentsTo');
    await Future.delayed(const Duration(seconds: 1));
    fileFrom.writeAsStringSync('contentsFrom');

    var stats = fileFrom.statSync();
    expect(fileTo.statSync().modified, isNot(equals(stats.modified)));

    expect(fileTo.readAsStringSync(), equals('contentsTo'));
    await updatePath(from.path, to.path);
    expect(fileTo.readAsStringSync(), equals('contentsFrom'));
  });

  test('updatePath does not update newer files', () async {
    var fileFrom = File(p.join(from.path, '1'));
    var fileTo = File(p.join(to.path, '1'));

    fileFrom.writeAsStringSync('contentsFrom');
    await Future.delayed(const Duration(seconds: 1));
    fileTo.writeAsStringSync('contentsTo');

    var stats = fileFrom.statSync();
    expect(fileTo.statSync().modified, isNot(equals(stats.modified)));

    await updatePath(from.path, to.path);
    expect(fileTo.statSync().modified, isNot(equals(stats.modified)));
    expect(fileTo.readAsStringSync(), equals('contentsTo'));
  });

  test('updatePath updates stale files and directories', () async {
    var subDirFrom = Directory(p.join(from.path, '1'));
    var subDirTo1 = Directory(p.join(to.path, '1'));
    var subDirTo2 = Directory(p.join(to.path, '2'));

    subDirFrom.createSync();
    subDirTo1.createSync();
    subDirTo2.createSync();

    var fileFrom = File(p.join(subDirFrom.path, 'a'));
    var fileTo1 = File(p.join(subDirTo1.path, 'a'));
    var fileTo2 = File(p.join(subDirTo2.path, 'b'));

    fileTo1.writeAsStringSync('contentsTo1');
    fileTo2.writeAsStringSync('contentsTo2');
    await Future.delayed(const Duration(seconds: 1));
    fileFrom.writeAsStringSync('contentsFrom');

    await updatePath(from.path, to.path);

    expect(fileTo1.readAsStringSync(), equals('contentsFrom'));
    expect(fileTo2.existsSync(), isFalse);
  });

  test('updatePath does not update newer files and directories', () async {
    var subDirFrom = Directory(p.join(from.path, '1'));
    var subDirTo1 = Directory(p.join(to.path, '1'));
    var subDirTo2 = Directory(p.join(to.path, '2'));

    subDirFrom.createSync();
    subDirTo1.createSync();
    subDirTo2.createSync();

    var fileFrom = File(p.join(subDirFrom.path, 'a'));
    var fileTo1 = File(p.join(subDirTo1.path, 'a'));
    var fileTo2 = File(p.join(subDirTo2.path, 'b'));

    fileFrom.writeAsStringSync('contentsFrom');
    await Future.delayed(const Duration(seconds: 1));
    fileTo1.writeAsStringSync('contentsTo1');
    fileTo2.writeAsStringSync('contentsTo2');

    await updatePath(from.path, to.path);

    expect(fileTo1.readAsStringSync(), equals('contentsTo1'));
    expect(fileTo2.existsSync(), isFalse);
  });
}
