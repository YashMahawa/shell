pragma Singleton

import Quickshell
import Caelestia
import Caelestia.Config
import qs.utils

Searcher {
    id: root
    
    property var searchResults: appDb.searchResults

    function launch(entry: DesktopEntry): void {
        appDb.incrementFrequency(entry.id);

        if (entry.runInTerminal)
            Quickshell.execDetached({
                command: ["app2unit", "--", ...GlobalConfig.general.apps.terminal, `${Quickshell.shellDir}/assets/wrap_term_launch.sh`, ...entry.command],
                workingDirectory: entry.workingDirectory
            });
        else
            Quickshell.execDetached({
                command: ["app2unit", "--", ...entry.command],
                workingDirectory: entry.workingDirectory
            });
    }

    function search(search: string): void {
        const prefix = GlobalConfig.launcher.specialPrefix;
        let keys = ["name"];
        let weights = [1];
        let actualSearch = search;
        let isTerminalOnly = false;

        if (search.startsWith(`${prefix}i `)) {
            keys = ["id", "name"];
            weights = [0.9, 0.1];
            actualSearch = search.slice(prefix.length + 2);
        } else if (search.startsWith(`${prefix}c `)) {
            keys = ["categories", "name"];
            weights = [0.9, 0.1];
            actualSearch = search.slice(prefix.length + 2);
        } else if (search.startsWith(`${prefix}d `)) {
            keys = ["comment", "name"];
            weights = [0.9, 0.1];
            actualSearch = search.slice(prefix.length + 2);
        } else if (search.startsWith(`${prefix}e `)) {
            keys = ["execString", "name"];
            weights = [0.9, 0.1];
            actualSearch = search.slice(prefix.length + 2);
        } else if (search.startsWith(`${prefix}w `)) {
            keys = ["startupClass", "name"];
            weights = [0.9, 0.1];
            actualSearch = search.slice(prefix.length + 2);
        } else if (search.startsWith(`${prefix}g `)) {
            keys = ["genericName", "name"];
            weights = [0.9, 0.1];
            actualSearch = search.slice(prefix.length + 2);
        } else if (search.startsWith(`${prefix}k `)) {
            keys = ["keywords", "name"];
            weights = [0.9, 0.1];
            actualSearch = search.slice(prefix.length + 2);
        } else if (search.startsWith(`${prefix}t `)) {
            isTerminalOnly = true;
            actualSearch = search.slice(prefix.length + 2);
        }

        appDb.searchAsync(actualSearch, keys, weights, isTerminalOnly, GlobalConfig.launcher.useFuzzy.apps);
    }

    function selector(item: var): string {
        return keys.map(k => item[k]).join(" ");
    }

    list: appDb.apps
    useFuzzy: GlobalConfig.launcher.useFuzzy.apps

    AppDb {
        id: appDb

        path: `${Paths.state}/apps.sqlite`
        favouriteApps: GlobalConfig.launcher.favouriteApps
        entries: DesktopEntries.applications.values.filter(a => !Strings.testRegexList(GlobalConfig.launcher.hiddenApps, a.id))
    }
}
