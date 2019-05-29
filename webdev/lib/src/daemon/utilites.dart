// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

dynamic toJsonable(dynamic obj) {
  if (obj is String ||
      obj is int ||
      obj is bool ||
      obj is Map<dynamic, dynamic> ||
      obj is List<dynamic> ||
      obj == null) return obj;
  return '$obj';
}

String getStringArg(Map<String, dynamic> args, String name,
    {bool required = false}) {
  if (required && !args.containsKey(name)) {
    throw ArgumentError('$name is required');
  }
  var val = args[name];
  if (val != null && val is! String) {
    throw ArgumentError('$name is not a String');
  }
  return val as String;
}

bool getBoolArg(Map<String, dynamic> args, String name,
    {bool required = false}) {
  if (required && !args.containsKey(name)) {
    throw ArgumentError('$name is required');
  }
  var val = args[name];
  if (val != null && val is! bool) throw ArgumentError('$name is not a bool');
  return val as bool;
}

int getIntArg(Map<String, dynamic> args, String name, {bool required = false}) {
  if (required && !args.containsKey(name)) {
    throw ArgumentError('$name is required');
  }
  var val = args[name];
  if (val != null && val is! int) throw ArgumentError('$name is not an int');
  return val as int;
}
