pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.utils

Singleton {
    id: root

    property var sourceBuckets: ({})
    property var holidayBuckets: ({})
    property var holidaysByDate: ({})
    property var loadedHolidayYears: ({})
    property var holidayCache: ({ version: 1, entries: ({}) })
    property bool holidayCacheReady: false
    property int revision: 0
    property int sourceGeneration: 0

    readonly property int holidayCacheMaxAgeMs: 7 * 24 * 60 * 60 * 1000

    readonly property string localeCountryCode: {
        const parts = Qt.locale().name.replace("-", "_").split("_");
        return parts.length > 1 ? parts[parts.length - 1].toUpperCase() : "";
    }
    readonly property string countryCode: {
        const configured = String(GlobalConfig.dashboard.calendarCountryCode ?? "").trim();
        return (configured || Weather.countryCode || localeCountryCode).toUpperCase();
    }

    function dateKey(date: date): string {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, "0");
        const day = String(date.getDate()).padStart(2, "0");
        return `${year}-${month}-${day}`;
    }

    function eventsForDate(date: date): list<var> {
        revision;
        const key = dateKey(date);
        const events = [];

        for (const bucket of Object.values(sourceBuckets)) {
            for (const event of bucket[key] ?? [])
                events.push(event);
        }

        for (const holiday of holidaysByDate[key] ?? [])
            events.push(holiday);

        return events.sort((a, b) => {
            if (a.holiday !== b.holiday)
                return a.holiday ? -1 : 1;
            return Number(a.startMs ?? 0) - Number(b.startMs ?? 0);
        });
    }

    function holidaysForDate(date: date): list<var> {
        revision;
        return holidaysByDate[dateKey(date)] ?? [];
    }

    function eventLoadForDate(date: date): int {
        revision;
        const key = dateKey(date);
        let minutes = 0;
        let count = 0;

        for (const bucket of Object.values(sourceBuckets)) {
            for (const event of bucket[key] ?? []) {
                if (!event.allDay) {
                    minutes += Math.max(1, Number(event.durationMinutes ?? 60));
                    count++;
                }
            }
        }

        if (count === 0)
            return 0;
        if (minutes <= 120 && count <= 2)
            return 1;
        if (minutes <= 300 && count <= 4)
            return 2;
        return 3;
    }

    function reload(): void {
        sourceGeneration++;
        sourceBuckets = {};
        revision++;

        const generation = sourceGeneration;
        const sources = GlobalConfig.dashboard.calendarSources ?? [];
        for (let index = 0; index < sources.length; index++) {
            const value = sources[index];
            const url = typeof value === "string" ? value : String(value?.url ?? "");
            const name = typeof value === "string" ? qsTr("Calendar") : String(value?.name ?? qsTr("Calendar"));
            if (!url)
                continue;

            const requestUrl = url.startsWith("/") ? `file://${url}` : url;
            Requests.get(requestUrl, text => {
                if (generation !== sourceGeneration)
                    return;
                const buckets = Object.assign({}, sourceBuckets);
                buckets[`${index}:${url}`] = parseIcalendar(text, name);
                sourceBuckets = buckets;
                revision++;
            }, error => console.warn(lc, `Unable to load calendar source ${index + 1}: ${error}`));
        }

        ensureYear(new Date().getFullYear());
        ensureYear(new Date().getFullYear() + 1);
    }

    function ensureYear(year: int): void {
        if (!GlobalConfig.dashboard.showNationalHolidays || !countryCode || !holidayCacheReady)
            return;

        const cacheKey = `${countryCode}:${year}`;
        if (loadedHolidayYears[cacheKey])
            return;

        const loading = Object.assign({}, loadedHolidayYears);
        loading[cacheKey] = true;
        loadedHolidayYears = loading;

        const cached = holidayCache.entries?.[cacheKey];
        if (cached?.holidays?.length) {
            applyHolidays(cached.holidays, cacheKey);
            if (Date.now() - Number(cached.fetchedAt ?? 0) < holidayCacheMaxAgeMs)
                return;
        }

        fetchGoogleHolidays(year, countryCode, cacheKey);
    }

    function googleHolidayCalendarId(code: string): string {
        // Most Google holiday calendars use the ISO alpha-2 code. Only the
        // irregular identifiers need listing; these are identifiers, not dates.
        const overrides = {
            AU: "australian", AT: "austrian", BR: "brazilian", BG: "bulgarian",
            CA: "canadian", CN: "china", HR: "croatian", CZ: "czech", DK: "danish",
            FI: "finnish", FR: "french", DE: "german", GR: "greek", HK: "hong_kong",
            HU: "hungarian", IN: "indian", ID: "indonesian", IE: "irish", IL: "jewish",
            IT: "italian", JP: "japanese", LV: "latvian", LT: "lithuanian",
            MY: "malaysia", MX: "mexican", NL: "dutch", NZ: "new_zealand",
            NO: "norwegian", PH: "philippines", PL: "polish", PT: "portuguese",
            KR: "south_korea", RO: "romanian", RU: "russian", SA: "saudiarabian",
            SG: "singapore", SK: "slovak", SI: "slovenian", ZA: "sa", ES: "spain",
            SE: "swedish", TW: "taiwan", TR: "turkish", UA: "ukrainian",
            GB: "uk", US: "usa", VN: "vietnamese"
        };
        const slug = overrides[code] ?? code.toLowerCase();
        return `en.${slug}#holiday@group.v.calendar.google.com`;
    }

    function fetchGoogleHolidays(year: int, code: string, cacheKey: string): void {
        const calendarId = encodeURIComponent(googleHolidayCalendarId(code));
        const url = `https://calendar.google.com/calendar/ical/${calendarId}/public/basic.ics`;
        Requests.get(url, text => {
            const values = parseGooglePublicHolidays(text, year);
            if (values.length === 0) {
                fetchNagerHolidays(year, code, cacheKey);
                return;
            }

            cacheAndApplyHolidays(cacheKey, code, year, values, "google-calendar");
        }, error => fetchNagerHolidays(year, code, cacheKey));
    }

    function fetchNagerHolidays(year: int, code: string, cacheKey: string): void {
        Requests.get(`https://date.nager.at/api/v3/PublicHolidays/${year}/${code}`, text => {
            if (!text.trim()) {
                holidayFetchFailed(cacheKey, qsTr("No public holiday data returned"));
                return;
            }

            let values;
            try {
                values = JSON.parse(text);
            } catch (error) {
                holidayFetchFailed(cacheKey, error);
                return;
            }

            if (!Array.isArray(values) || values.length === 0) {
                holidayFetchFailed(cacheKey, qsTr("No public holiday data returned"));
                return;
            }

            cacheAndApplyHolidays(cacheKey, code, year, values, "nager-date");
        }, error => holidayFetchFailed(cacheKey, error));
    }

    function holidayFetchFailed(cacheKey: string, error: var): void {
        // Stale cached data remains visible while offline or when a provider is
        // temporarily unavailable. Only make uncached failures retryable.
        if (!holidayCache.entries?.[cacheKey]) {
            console.warn(lc, `Unable to load national holidays for ${cacheKey}: ${error}`);
            const retryable = Object.assign({}, loadedHolidayYears);
            delete retryable[cacheKey];
            loadedHolidayYears = retryable;
        }
    }

    function cacheAndApplyHolidays(cacheKey: string, code: string, year: int, values: list<var>, source: string): void {
        const entries = Object.assign({}, holidayCache.entries ?? {});
        entries[cacheKey] = {
            countryCode: code,
            year,
            fetchedAt: Date.now(),
            source,
            holidays: values
        };
        holidayCache = { version: 1, entries };
        holidayCacheFile.setText(JSON.stringify(holidayCache));
        // Country detection can finish while an earlier locale-based request is
        // still in flight. Cache that response, but never display it for the
        // newly detected country.
        if (code === countryCode)
            applyHolidays(values, cacheKey);
    }

    function applyHolidays(values: list<var>, cacheKey: string): void {
        const bucket = {};
        for (const value of values) {
            if (value.global === false)
                continue;
            const key = String(value.date ?? "");
            if (!/^\d{4}-\d{2}-\d{2}$/.test(key))
                continue;
            const holiday = {
                title: String(value.localName || value.name || qsTr("Public holiday")),
                holiday: true,
                allDay: true,
                source: qsTr("National holiday")
            };
            if (!(bucket[key] ?? []).some(existing => existing.title === holiday.title))
                bucket[key] = (bucket[key] ?? []).concat([holiday]);
        }

        const buckets = Object.assign({}, holidayBuckets);
        buckets[cacheKey] = bucket;
        holidayBuckets = buckets;

        const merged = {};
        for (const value of Object.values(buckets)) {
            for (const [key, holidays] of Object.entries(value))
                merged[key] = (merged[key] ?? []).concat(holidays);
        }
        holidaysByDate = merged;
        revision++;
    }

    function parseGooglePublicHolidays(text: string, year: int): list<var> {
        const unfolded = text.replace(/\r?\n[ \t]/g, "");
        const values = [];
        for (const block of unfolded.split("BEGIN:VEVENT").slice(1)) {
            const dateMatch = block.match(/(?:^|\n)DTSTART(?:;[^:]*)?:(\d{8})(?:\r?\n|$)/);
            const titleMatch = block.match(/(?:^|\n)SUMMARY(?:;[^:]*)?:(.*?)(?:\r?\n|$)/);
            const descriptionMatch = block.match(/(?:^|\n)DESCRIPTION(?:;[^:]*)?:(.*?)(?:\r?\n|$)/);
            if (!dateMatch || !titleMatch || !descriptionMatch)
                continue;
            if (!descriptionMatch[1].toLowerCase().startsWith("public holiday"))
                continue;

            const raw = dateMatch[1];
            if (Number(raw.slice(0, 4)) !== year)
                continue;
            values.push({
                date: `${raw.slice(0, 4)}-${raw.slice(4, 6)}-${raw.slice(6, 8)}`,
                localName: unescapeIcalendar(titleMatch[1]),
                global: true
            });
        }
        return values;
    }

    function parseIcalendar(text: string, sourceName: string): var {
        const unfolded = text.replace(/\r?\n[ \t]/g, "");
        const lines = unfolded.split(/\r?\n/);
        const result = {};
        let event = null;

        for (const line of lines) {
            if (line === "BEGIN:VEVENT") {
                event = {};
                continue;
            }
            if (line === "END:VEVENT") {
                if (event)
                    expandEvent(event, sourceName, result);
                event = null;
                continue;
            }
            if (!event)
                continue;

            const separator = line.indexOf(":");
            if (separator < 0)
                continue;
            const head = line.slice(0, separator).split(";");
            const key = head.shift().toUpperCase();
            const params = {};
            for (const item of head) {
                const equals = item.indexOf("=");
                if (equals > 0)
                    params[item.slice(0, equals).toUpperCase()] = item.slice(equals + 1);
            }
            const value = line.slice(separator + 1);

            if (key === "DTSTART")
                event.start = parseIcalendarDate(value, params);
            else if (key === "DTEND")
                event.end = parseIcalendarDate(value, params);
            else if (key === "SUMMARY")
                event.title = unescapeIcalendar(value);
            else if (key === "CATEGORIES")
                event.category = unescapeIcalendar(value.split(",")[0]).trim().toLowerCase();
            else if (key === "RRULE")
                event.rule = parseRule(value);
            else if (key === "EXDATE") {
                if (!event.exdates)
                    event.exdates = [];
                for (const dateValue of value.split(",")) {
                    const parsed = parseIcalendarDate(dateValue, params);
                    if (parsed)
                        event.exdates.push(dateKey(parsed.date));
                }
            }
        }

        return result;
    }

    function parseIcalendarDate(value: string, params: var): var {
        const raw = value.trim();
        const match = raw.match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$/);
        if (!match)
            return null;

        const allDay = params.VALUE === "DATE" || !match[4];
        const values = [Number(match[1]), Number(match[2]) - 1, Number(match[3]), Number(match[4] ?? 0), Number(match[5] ?? 0), Number(match[6] ?? 0)];
        const date = match[7] ? new Date(Date.UTC(...values)) : new Date(...values);
        return { date, allDay };
    }

    function parseRule(value: string): var {
        const rule = {};
        for (const part of value.split(";")) {
            const separator = part.indexOf("=");
            if (separator > 0)
                rule[part.slice(0, separator).toUpperCase()] = part.slice(separator + 1);
        }
        return rule;
    }

    function expandEvent(event: var, sourceName: string, target: var): void {
        if (!event.start?.date)
            return;

        const start = event.start.date;
        const end = event.end?.date ?? new Date(start.getTime() + (event.start.allDay ? 86400000 : 3600000));
        const durationMinutes = Math.max(0, Math.round((end.getTime() - start.getTime()) / 60000));
        const excluded = new Set(event.exdates ?? []);
        const now = new Date();
        const rangeStart = new Date(now.getFullYear() - 1, 0, 1);
        const rangeEnd = new Date(now.getFullYear() + 3, 0, 1);

        const append = occurrence => {
            const key = dateKey(occurrence);
            if (excluded.has(key))
                return;
            const value = {
                title: event.title || qsTr("Untitled event"),
                holiday: false,
                allDay: event.start.allDay,
                source: sourceName,
                category: event.category || "event",
                startMs: occurrence.getTime(),
                durationMinutes
            };
            target[key] = (target[key] ?? []).concat([value]);
        };

        if (!event.rule?.FREQ) {
            if (event.start.allDay) {
                // DTEND is exclusive for all-day iCalendar events. Expand the
                // range so breaks and multi-day examinations appear on every
                // affected date rather than only their first day.
                const cursor = new Date(start.getFullYear(), start.getMonth(), start.getDate());
                while (cursor < end && cursor < rangeEnd) {
                    if (cursor >= rangeStart)
                        append(new Date(cursor));
                    cursor.setDate(cursor.getDate() + 1);
                }
            } else if (start >= rangeStart && start < rangeEnd) {
                append(start);
            }
            return;
        }

        const frequency = String(event.rule.FREQ).toUpperCase();
        if (frequency !== "DAILY" && frequency !== "WEEKLY") {
            if (start >= rangeStart && start < rangeEnd)
                append(start);
            return;
        }

        const interval = Math.max(1, Number(event.rule.INTERVAL ?? 1));
        const countLimit = Math.max(0, Number(event.rule.COUNT ?? 0));
        const untilParsed = event.rule.UNTIL ? parseIcalendarDate(event.rule.UNTIL, {}) : null;
        const until = untilParsed?.date ?? rangeEnd;
        const dayCodes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];
        const byDays = String(event.rule.BYDAY ?? dayCodes[start.getDay()]).split(",").map(value => value.slice(-2));
        const originalDay = new Date(start.getFullYear(), start.getMonth(), start.getDate());
        let cursor = new Date(originalDay);
        let occurrences = 0;

        while (cursor < rangeEnd && cursor <= until) {
            const elapsedDays = Math.floor((cursor.getTime() - originalDay.getTime()) / 86400000);
            const intervalMatches = frequency === "DAILY" ? elapsedDays % interval === 0 : Math.floor(elapsedDays / 7) % interval === 0;
            const dayMatches = frequency === "DAILY" || byDays.includes(dayCodes[cursor.getDay()]);

            if (elapsedDays >= 0 && intervalMatches && dayMatches) {
                occurrences++;
                if (countLimit > 0 && occurrences > countLimit)
                    break;
                if (cursor >= rangeStart) {
                    append(new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate(), start.getHours(), start.getMinutes(), start.getSeconds()));
                }
            }
            cursor.setDate(cursor.getDate() + 1);
        }
    }

    function unescapeIcalendar(value: string): string {
        return value.replace(/\\n/gi, " ").replace(/\\,/g, ",").replace(/\\;/g, ";").replace(/\\\\/g, "\\");
    }

    onCountryCodeChanged: {
        holidayBuckets = {};
        holidaysByDate = {};
        loadedHolidayYears = {};
        revision++;
        ensureYear(new Date().getFullYear());
        ensureYear(new Date().getFullYear() + 1);
    }

    Connections {
        function onCalendarSourcesChanged(): void {
            root.reload();
        }
        function onShowNationalHolidaysChanged(): void {
            root.holidayBuckets = {};
            root.holidaysByDate = {};
            root.loadedHolidayYears = {};
            root.revision++;
            root.ensureYear(new Date().getFullYear());
        }
        target: GlobalConfig.dashboard
    }

    FileView {
        id: holidayCacheFile

        path: `${Paths.cache}/holiday-cache-v1.json`
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (parsed?.version === 1 && typeof parsed.entries === "object")
                    root.holidayCache = parsed;
            } catch (error) {
                console.warn(lc, `Unable to parse holiday cache: ${error}`);
            }
            root.holidayCacheReady = true;
            root.ensureYear(new Date().getFullYear());
            root.ensureYear(new Date().getFullYear() + 1);
        }
        onLoadFailed: error => {
            root.holidayCacheReady = true;
            if (error === FileViewError.FileNotFound)
                Qt.callLater(() => setText(JSON.stringify(root.holidayCache)));
            root.ensureYear(new Date().getFullYear());
            root.ensureYear(new Date().getFullYear() + 1);
        }
    }

    Timer {
        interval: 1800000
        running: true
        repeat: true
        onTriggered: root.reload()
    }

    LoggingCategory {
        id: lc
        name: "caelestia.qml.services.calendar"
        defaultLogLevel: LoggingCategory.Info
    }
}
