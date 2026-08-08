pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root

    readonly property list<string> dayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    readonly property string configPath: `${Paths.config}/timetable.json`

    property var data: ({ version: 1, profile: "", termStart: "", termEnd: "", days: ({}) })
    property bool loaded: false
    property string error: ""

    function dateKey(date: date): string {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, "0");
        const day = String(date.getDate()).padStart(2, "0");
        return `${year}-${month}-${day}`;
    }

    function inTerm(date: date): bool {
        const key = dateKey(date);
        return (!data.termStart || key >= data.termStart) && (!data.termEnd || key <= data.termEnd);
    }

    function entriesForDay(day: string): list<var> {
        return data.days?.[day] ?? [];
    }

    function effectiveSchedule(date: date): var {
        const events = CalendarEvents.eventsForDate(date);
        const blocked = events.find(event => event.holiday
            || ["exam", "break", "no-class"].includes(String(event.category ?? "").toLowerCase())
            || /no classes|semester break|winter break|summer break|examinations?$/i.test(String(event.title ?? "")));
        if (blocked)
            return { day: dayNames[date.getDay()], adjusted: false, noClasses: true, reason: blocked.title };

        const adjustment = events.map(event => String(event.title ?? "").match(/^(Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday)(?:'s)? timetable (?:will be )?followed$/i))
            .find(match => match);
        const actualDay = dayNames[date.getDay()];
        const day = adjustment ? adjustment[1][0].toUpperCase() + adjustment[1].slice(1).toLowerCase() : actualDay;
        return {
            day,
            adjusted: day !== actualDay,
            actualDay,
            noClasses: !inTerm(date),
            reason: !inTerm(date) ? qsTr("Outside the active teaching term") : ""
        };
    }

    function scheduleForDate(date: date): list<var> {
        const effective = effectiveSchedule(date);
        if (!loaded || effective.noClasses)
            return [];
        return entriesForDay(effective.day).map(entry => Object.assign({}, entry, {
            effectiveDay: effective.day,
            adjusted: effective.adjusted
        }));
    }

    function minutes(value: string): int {
        const parts = value.split(":").map(Number);
        return (parts[0] || 0) * 60 + (parts[1] || 0);
    }

    function formatTime(value: string): string {
        const parts = value.split(":").map(Number);
        const hour = parts[0] || 0;
        const minute = parts[1] || 0;
        const suffix = hour >= 12 ? "PM" : "AM";
        const displayHour = hour % 12 || 12;
        return minute === 0 ? `${displayHour} ${suffix}` : `${displayHour}:${String(minute).padStart(2, "0")} ${suffix}`;
    }

    function eventsForDate(date: date): list<var> {
        return scheduleForDate(date).map(entry => {
            const startParts = entry.start.split(":").map(Number);
            const start = new Date(date.getFullYear(), date.getMonth(), date.getDate(), startParts[0], startParts[1]);
            return {
                title: `${entry.course} · ${formatTime(entry.start)}–${formatTime(entry.end)}`,
                detail: entry.room && entry.room !== "TBA" ? entry.room : "",
                holiday: false,
                allDay: false,
                category: "class",
                source: qsTr("Timetable"),
                startMs: start.getTime(),
                durationMinutes: Math.max(1, minutes(entry.end) - minutes(entry.start))
            };
        });
    }

    function loadForDate(date: date): int {
        const entries = scheduleForDate(date);
        if (entries.length === 0)
            return 0;
        const total = entries.reduce((sum, entry) => sum + Math.max(1, minutes(entry.end) - minutes(entry.start)), 0);
        if (total <= 120 && entries.length <= 2)
            return 1;
        if (total <= 240 && entries.length <= 4)
            return 2;
        return 3;
    }

    function reload(): void {
        configFile.reload();
    }

    FileView {
        id: configFile

        path: root.configPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (!parsed?.days || typeof parsed.days !== "object")
                    throw new Error("Missing timetable days");
                root.data = parsed;
                root.error = "";
                root.loaded = true;
            } catch (error) {
                root.error = String(error);
                root.loaded = false;
            }
        }
        onLoadFailed: error => {
            root.error = error === FileViewError.FileNotFound ? qsTr("No timetable configured") : String(error);
            root.loaded = false;
        }
    }
}
