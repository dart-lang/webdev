// Copyright 2023 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

@Timeout(Duration(minutes: 1))
import 'package:dwds/src/utilities/shared.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import 'fixtures/context.dart';

void main() {
  group('wrapInErrorHandlerAsync', () {
    test('returns future success value if callback succeeds', () async {
      Future<bool> successCallback() async {
        await Future.delayed(Duration(milliseconds: 500));
        return true;
      }

      final result =
          await wrapInErrorHandlerAsync('successCallback', successCallback);
      expect(result, equals(true));
    });

    test('throws RPCError if callback throws RPCError', () async {
      Future<bool> rpcErrorCallback() async {
        await Future.delayed(Duration(milliseconds: 500));
        throw RPCError(
          'rpcErrorCallback',
          RPCErrorKind.kInvalidRequest.code,
          'An error message',
        );
      }

      try {
        await wrapInErrorHandlerAsync('rpcErrorCallback', rpcErrorCallback);
        fail("RPCError not thrown.");
      } catch (error) {
        expect(error, isRPCErrorWithMessage('An error message'));
      }
    });

    test('throws RPCError if callback throws other error type', () async {
      Future<bool> exceptionCallback() async {
        await Future.delayed(Duration(milliseconds: 500));
        throw Exception('An unexpected exception');
      }

      try {
        await wrapInErrorHandlerAsync('exceptionCallback', exceptionCallback);
        fail("RPCError not thrown.");
      } catch (error) {
        expect(
          error,
          isRPCErrorWithMessage(
            'Unexpected DWDS error for exceptionCallback: Exception: An unexpected exception',
          ),
        );
      }
    });
  });
}
