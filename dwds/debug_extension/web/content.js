document.addEventListener('dart-app-ready', function (e) {
    chrome.runtime.sendMessage(e, function (response) {
    });
});
