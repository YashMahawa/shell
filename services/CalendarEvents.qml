pragma Singleton

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config

Singleton {
    id: root

    property var sourceBuckets: ({})
    property var holidaysByDate: ({})
    property var loadedHolidayYears: ({})
    property int revision: 0
    property int sourceGeneration: 0

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
        if (!GlobalConfig.dashboard.showNationalHolidays || !countryCode)
            return;

        const cacheKey = `${countryCode}:${year}`;
        if (loadedHolidayYears[cacheKey])
            return;

        const loading = Object.assign({}, loadedHolidayYears);
        loading[cacheKey] = true;
        loadedHolidayYears = loading;

        Requests.get(`https://date.nager.at/api/v3/PublicHolidays/${year}/${countryCode}`, text => {
            if (!text.trim()) {
                applyHolidays(builtinNationalHolidays(year, countryCode));
                return;
            }

            let values;
            try {
                values = JSON.parse(text);
            } catch (error) {
                console.warn(lc, `Unable to parse national holidays: ${error}`);
                return;
            }

            if (!Array.isArray(values))
                return;

            applyHolidays(values);
        }, error => {
            const fallback = builtinNationalHolidays(year, countryCode);
            if (fallback.length > 0) {
                applyHolidays(fallback);
                return;
            }
            console.warn(lc, `Unable to load national holidays for ${countryCode}: ${error}`);
            const retryable = Object.assign({}, loadedHolidayYears);
            delete retryable[cacheKey];
            loadedHolidayYears = retryable;
        });
    }

    function applyHolidays(values: list<var>): void {
        const next = Object.assign({}, holidaysByDate);
        for (const value of values) {
            // API v3 calls this field "global". Only globally applicable
            // public holidays are shown; regional observances stay hidden.
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
            next[key] = (next[key] ?? []).concat([holiday]);
        }
        holidaysByDate = next;
        revision++;
    }

    function builtinNationalHolidays(year: int, code: string): list<var> {
        // Nager.Date intentionally omits India because most Indian public
        // holidays vary by state. These three are the fixed, country-wide
        // national holidays, so they are safe to provide without regional noise.
        if (code === "IN") {
            return [{
                date: `${year}-01-26`,
                localName: qsTr("Republic Day"),
                global: true
            }, {
                date: `${year}-08-15`,
                localName: qsTr("Independence Day"),
                global: true
            }, {
                date: `${year}-10-02`,
                localName: qsTr("Gandhi Jayanti"),
                global: true
            }];
        }
        return [];
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
                startMs: occurrence.getTime(),
                durationMinutes
            };
            target[key] = (target[key] ?? []).concat([value]);
        };

        if (!event.rule?.FREQ) {
            if (start >= rangeStart && start < rangeEnd)
                append(start);
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
            root.holidaysByDate = {};
            root.loadedHolidayYears = {};
            root.revision++;
            root.ensureYear(new Date().getFullYear());
        }
        target: GlobalConfig.dashboard
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
