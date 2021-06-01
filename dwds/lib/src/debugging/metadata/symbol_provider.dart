// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

// @dart = 2.9

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:logging/logging.dart';

import '../../readers/asset_reader.dart';
import 'module_metadata.dart';
import 'module_symbols.dart';

class SymbolTableProvider {
  final AssetReader _assetReader;
  final _logger = Logger('SymbolTableProvider');
  final _symbolTableMemoizer = AsyncMemoizer();
  final SymbolTable _symbolTable = SymbolTable();
  final String entrypoint;

  SymbolTableProvider(this.entrypoint, this._assetReader);

  Future<SymbolTable> get symbolTable async {
    await _symbolTableMemoizer.future;
    return _symbolTable;
  }

  Future<void> initialize(Map<String, ModuleInfo> modules) async {
    await _symbolTableMemoizer.runOnce(() async {
      _logger.info('Loading debug symbols...');
      _logger.info('modules: $modules');

      for (var module in modules.keys) {
        var symbolsPath = modules[module].symbolsPath;
        var symbols = await _assetReader.symbolsContents(symbolsPath);
        if (symbols != null) {
          try {
            var symbolsJson = json.decode(symbols) as Map<String, dynamic>;
            var moduleSymbols = ModuleSymbols.fromJson(symbolsJson);
            _symbolTable.addSymbols(moduleSymbols);
            _logger.fine('Loaded debug symbols for module: $module');
          } catch (e) {
            _logger.severe('Failed to read symbols for $module: $e');
            rethrow;
          }
        } else {
          _logger.severe('Cannot find symbols file for $module');
        }
      }

      _logger.info('Loaded debug symbols.');
    });
  }
}

/// A provider of debug symbols read from symbols information stored by DDC.
class SymbolTable {
  final Map<String, LibrarySymbol> libraries = {};
  final Map<String, Script> scripts = {};
  final Map<String, ClassSymbol> classes = {};
  final Map<String, FunctionTypeSymbol> functionTypes = {};
  final Map<String, TypeSymbol> types = {};
  final Map<String, FunctionSymbol> functions = {};
  final Map<String, ScopeSymbol> scopes = {};
  final Map<String, VariableSymbol> variables = {};

  SymbolTable();

  void addSymbols(ModuleSymbols symbols) {
    for (var element in symbols.libraries) {
      if (libraries.containsKey(element.id)) {
        throw Exception('Library already added: ${element.id}');
      }
      libraries[element.id] = element;
      scopes[element.id] = element;
    }
    for (var element in symbols.scripts) {
      if (scripts.containsKey(element.id)) {
        throw Exception('Script already added: ${element.id}');
      }
      scripts[element.id] = element;
    }
    for (var element in symbols.classes) {
      if (classes.containsKey(element.id)) {
        throw Exception('Class already added: ${element.id}');
      }
      classes[element.id] = element;
      scopes[element.id] = element;
      types[element.id] = element;
    }
    for (var element in symbols.functionTypes) {
      functionTypes[element.id] = element;
      types[element.id] = element;
    }
    for (var element in symbols.functions) {
      if (functions.containsKey(element.id)) {
        throw Exception('Function already added: ${element.id}');
      }
      functions[element.id] = element;
      scopes[element.id] = element;
    }
    for (var element in symbols.scopes) {
      if (scopes.containsKey(element.id)) {
        throw Exception('Scope already added: ${element.id}');
      }
      scopes[element.id] = element;
    }
    for (var element in symbols.variables) {
      if (variables.containsKey(element.id)) {
        throw Exception('Variable already added: ${element.id}');
      }
      variables[element.id] = element;
    }
  }
}
