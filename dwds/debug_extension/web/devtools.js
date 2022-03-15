(function loadDevToolsScript() {
  const DDR_DART_APP_ATTRIBUTE = 'data-ddr-dart-app';
  let created = false;
  let checkDartCount = 0;
  let checkFlutterCount = 0;

  chrome.devtools.network.onNavigated.addListener(createPanelIfDartApp)
  const checkDartAppInterval = setInterval(createPanelIfDartApp, 1000)
  createPanelIfDartApp()

  function createPanelIfDartApp() {
    if (created || checkDartCount++ > 20) {
      clearInterval(checkDartAppInterval);
      return;
    }

    checkIsDartApp();
  }

  function checkIsDartApp() {
    // TODO(elliette): Remove the DDR data attribute check when we are ready to launch externally,
    // and instead replace it with the following: !!window.$dartAppId 
    // Note: we must remove the useContentScriptContext option as well.
    chrome.devtools.inspectedWindow.eval(
      `document.documentElement.hasAttribute("${DDR_DART_APP_ATTRIBUTE}")`,
      { useContentScriptContext: true },
      function (isDartApp) {
        if (!isDartApp) return;
        checkIsAngularApp();
      });
  }

  function checkIsAngularApp() {
    chrome.devtools.inspectedWindow.eval('window.$isAngularApp',
      function (angularAppMode) {
        // If the value is 'debug', then this is an Angular app 
        // and we can create the Dart Debugger panel immediately:
        if (angularAppMode == 'debug') {
          created = true;
          chrome.devtools.panels.create(
            'Dart Debugger', '', 'debugger_panel.html'
          );
        // Otherwise, clear the interval checking for a Dart app
        // and instead check to see if this is a Flutter app:
        } else {
          clearInterval(checkDartAppInterval);
          createPanelsIfFlutterApp();
        }
      });
  }

  function createPanelsIfFlutterApp() {
    const checkFlutterAppInterval = setInterval(function() {
      if (checkFlutterCount++ > 10) {
        // If Flutter is not detected after 10 seconds, still
        // create the Dart Debugger panel:
        clearInterval(checkFlutterAppInterval);
        chrome.devtools.panels.create(
          'Dart Debugger', '', 'debugger_panel.html'
        );
      }

      // The following value is loaded asynchronously, which is why
      // we check for it every 1 second:
      chrome.devtools.inspectedWindow.eval(
        '!!window._flutter_web_set_location_strategy',
        function (isFlutterWeb) {
          if (isFlutterWeb) {
            clearInterval(checkFlutterAppInterval);
            chrome.devtools.panels.create(
                'Flutter Debugger', '', 'debugger_panel.html'
              );
              chrome.devtools.panels.create(
                'Flutter Inspector', '', 'inspector_panel.html'
              );
            }
        }
      );
    }, 1000)
  }
}());

