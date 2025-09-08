// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'serializers.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializers _$serializers =
    (Serializers().toBuilder()
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
          ..add(HotReloadRequest.serializer)
          ..add(HotReloadResponse.serializer)
          ..add(HotRestartRequest.serializer)
          ..add(HotRestartResponse.serializer)
          ..add(IsolateExit.serializer)
          ..add(IsolateStart.serializer)
          ..add(RegisterEvent.serializer)
          ..add(RunRequest.serializer)
          ..add(ServiceExtensionRequest.serializer)
          ..add(ServiceExtensionResponse.serializer)
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(DebugEvent)]),
            () => ListBuilder<DebugEvent>(),
          )
          ..addBuilderFactory(
            const FullType(BuiltList, const [const FullType(ExtensionEvent)]),
            () => ListBuilder<ExtensionEvent>(),
          ))
        .build();

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
