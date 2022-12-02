async () => {
    const targets = await chrome.debugger.getTargets();
    const tab = targets.filter((target) => target.id == tabId);
    return tab.attached;
  }