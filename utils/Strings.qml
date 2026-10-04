pragma Singleton

import Quickshell

Singleton {
    property var _regexCache: ({})

    function friendlyAppName(appId: string): string {
        if (!appId)
            return "";

        // Chromium generates URL-derived Wayland app IDs for --app windows.
        // Prefer the matching desktop entry's human-readable name.
        const entry = DesktopEntries.heuristicLookup(appId);
        if (entry?.name)
            return entry.name;

        if (appId.startsWith("chrome-gemini.google.com__app"))
            return "Gemini";

        return appId;
    }

    function testRegexList(filterList: list<string>, target: string): bool {
        const regexChecker = /^\^.*\$$/;
        for (const filter of filterList) {
            if (regexChecker.test(filter)) {
                let re = _regexCache[filter];
                if (!re) {
                    re = new RegExp(filter);
                    _regexCache[filter] = re;
                }
                if (re.test(target))
                    return true;
            } else {
                if (filter === target)
                    return true;
            }
        }
        return false;
    }
}
