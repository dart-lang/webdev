// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'serializers.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializers _$serializers = (new Serializers().toBuilder()
      ..add(BatchedDebugEvents.serializer)
      ..add(BatchedEvents.serializer)
      ..add(BuildResult.serializer)
      ..add(BuildStatus.serializer)
      ..add(ConnectRequest.serializer)
      ..add(DebugEvent.serializer)
      ..add(DebugInfo.serializer)
      ..add(DevToolsRequest.serializer)
      ..add(DevToolsResponse.serializer)
      ..add(ErrorResponse.serializer)
      ..add(ExtensionEvent.serializer)
      ..add(ExtensionRequest.serializer)
      ..add(ExtensionResponse.serializer)
      ..add(IsolateExit.serializer)
      ..add(IsolateStart.serializer)
      ..add(RegisterEntrypointRequest.serializer)
      ..add(RegisterEvent.serializer)
      ..add(RunRequest.serializer)
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(DebugEvent)]),
          () => new ListBuilder<DebugEvent>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(ExtensionEvent)]),
          () => new ListBuilder<ExtensionEvent>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => new ListBuilder<String>()))
    .build();

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
