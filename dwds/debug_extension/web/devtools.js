(function loadDevToolsScript() {
  const DDR_DART_APP_ATTRIBUTE = 'data-ddr-dart-app';
  let created = false;
  let checkCount = 0;

  chrome.devtools.network.onNavigated.addListener(createPanelIfDartApp)
  const checkDartAppInterval = setInterval(createPanelIfDartApp, 1000)
  createPanelIfDartApp()

  function createPanelIfDartApp() {
    if (created || checkCount++ > 20) {
      clearInterval(checkDartAppInterval);
      return;
    }

    // TODO(elliette): Remove the DDR data attribute check when we are ready to launch externally,
    // and instead replace it with the following: !!window.$dartAppId 
    // Note: we must remove the useContentScriptContext option as well.
    chrome.devtools.inspectedWindow.eval(
      `document.documentElement.hasAttribute("${DDR_DART_APP_ATTRIBUTE}")`,
      {useContentScriptContext: true}, 
      function (isDartApp) {
        if (isDartApp) {
          created = true
          chrome.devtools.panels.create(
            'Dart', '', 'panel.html'
          );
        }
      },
    )
  }
}());

