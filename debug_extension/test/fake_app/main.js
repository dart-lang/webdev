document.addEventListener("DOMContentLoaded", function(event) { 
    window['$dartEntrypointPath'] = 'DART_ENTRYPOINT_PATH';
    window['$dartAppId'] = 'DART_APP_ID';
    window['$dartAppInstanceId'] = 'DART_APP_INSTANCE_ID';
    window['$dartExtensionUri'] = 'http://localhost:8080/extensionPath';
    window['$isInternalBuild'] = true;
    window['$isFlutterApp'] = false;
    setTimeout(() => {
        window.top.document.dispatchEvent(new CustomEvent('dart-app-ready'));
    }, 1000);
  });
