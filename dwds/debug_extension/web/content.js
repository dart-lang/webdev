var hasSent = false;

function sendMessage(e) {
    if (hasSent) return;
    hasSent = true;
    chrome.runtime.sendMessage(e, function (response) {
    });
}

document.addEventListener('dart-app-ready', function (e) {
    sendMessage(e);
});

var targetNode = document;
var observerOptions = {
    childList: true,
    attributes: true,
    subtree: true
};

function callback(mutationList, observer) {
    mutationList.forEach((mutation) => {
        if (mutation.type == 'childList') {
            var addedNodes = mutation.addedNodes
            for (var i = 0; i < addedNodes.length; i++) {
                if (addedNodes[i].tagName == 'SCRIPT' &&
                    addedNodes[i].src.includes('dart_sdk.js')) {
                    sendMessage({});
                }
            }
        }
    });
}

// TODO(grouma) - This will become unnecessary when package:dwds version 11.0.0
// hits Flutter stable.
var observer = new MutationObserver(callback);
observer.observe(targetNode, observerOptions);

