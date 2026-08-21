pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils

StyledClippingRect {
    id: root

    property string initialPage: "calendar"
    property int currentPage: Math.max(0, ["calendar", "timetable", "settings"].indexOf(initialPage))
    property date selectedDate: new Date()
    property int shownMonth: selectedDate.getMonth()
    property int shownYear: selectedDate.getFullYear()
    signal closeRequested()

    readonly property var pages: [
        { key: "calendar", title: qsTr("Calendar"), subtitle: qsTr("Month and day details"), icon: "calendar_month" },
        { key: "timetable", title: qsTr("Timetable"), subtitle: qsTr("Weekly class schedule"), icon: "view_week" },
        { key: "settings", title: qsTr("Settings"), subtitle: qsTr("Sources and holidays"), icon: "tune" }
    ]
    readonly property list<var> selectedEvents: combinedEvents(selectedDate)
    readonly property var selectedSchedule: Timetable.effectiveSchedule(selectedDate)

    function combinedEvents(date: date): list<var> {
        return [...CalendarEvents.eventsForDate(date), ...Timetable.eventsForDate(date)].sort((a, b) => {
            if (a.holiday !== b.holiday)
                return a.holiday ? -1 : 1;
            return Number(a.startMs ?? 0) - Number(b.startMs ?? 0);
        });
    }

    function category(event: var): string {
        if (!event)
            return "event";
        if (event.holiday)
            return "holiday";
        const explicit = String(event.category ?? "").toLowerCase();
        if (explicit && explicit !== "event")
            return explicit;
        const title = String(event.title ?? "").toLowerCase();
        if (/exam|minor|major|test/.test(title)) return "exam";
        if (/break|vacation|no class|festival/.test(title)) return "break";
        if (/deadline|registration|add\/drop|withdraw|grade|reporting/.test(title)) return "deadline";
        if (/timetable|class|lecture|lab|tutorial| tut/.test(title)) return "class";
        return "event";
    }

    function categoryColour(value: string): color {
        switch (value) {
        case "exam": return Colours.palette.m3error;
        case "break":
        case "no-class": return Colours.palette.m3secondary;
        case "holiday":
        case "class":
        case "schedule": return Colours.palette.m3tertiary;
        default: return Colours.palette.m3primary;
        }
    }

    function selectDate(date: date): void {
        selectedDate = date;
        shownMonth = date.getMonth();
        shownYear = date.getFullYear();
    }

    implicitWidth: 1120
    implicitHeight: 740
    width: implicitWidth
    height: implicitHeight
    radius: Tokens.rounding.extraLarge
    color: Colours.tPalette.m3surfaceContainer
    border.width: 1
    border.color: Colours.palette.m3outlineVariant

    onInitialPageChanged: currentPage = Math.max(0, ["calendar", "timetable", "settings"].indexOf(initialPage))

    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        StyledRect {
            Layout.preferredWidth: 250
            Layout.fillHeight: true
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainerHigh

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Tokens.padding.large
                    spacing: Tokens.spacing.medium
                    StyledRect {
                        implicitWidth: 46
                        implicitHeight: 46
                        radius: 16
                        color: Colours.palette.m3primaryContainer
                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "calendar_month"
                            fill: 1
                            color: Colours.palette.m3onPrimaryContainer
                            fontStyle: Tokens.font.icon.medium
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { text: qsTr("Calendar"); font: Tokens.font.title.medium; color: Colours.palette.m3onSurface }
                    }
                }

                Repeater {
                    model: root.pages
                    delegate: StyledRect {
                        id: nav
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 64
                        radius: Tokens.rounding.large
                        color: index === root.currentPage ? Colours.palette.m3secondaryContainer : "transparent"
                        StateLayer { onClicked: root.currentPage = nav.index }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            spacing: Tokens.spacing.medium
                            MaterialIcon {
                                text: nav.modelData.icon
                                color: nav.index === root.currentPage ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.medium
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText { text: nav.modelData.title; font: Tokens.font.body.medium; color: Colours.palette.m3onSurface }
                                StyledText { Layout.fillWidth: true; text: nav.modelData.subtitle; font: Tokens.font.label.small; color: Colours.palette.m3onSurfaceVariant; elide: Text.ElideRight }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 74
                    radius: Tokens.rounding.large
                    color: Colours.palette.m3tertiaryContainer
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        spacing: 0
                        StyledText { text: Qt.locale().toString(new Date(), "dddd"); color: Colours.palette.m3onTertiaryContainer; font: Tokens.font.label.medium }
                        StyledText {
                            text: {
                                const schedule = Timetable.effectiveSchedule(new Date());
                                if (schedule.noClasses) return schedule.reason || qsTr("No classes");
                                const count = Timetable.scheduleForDate(new Date()).length;
                                return schedule.adjusted ? qsTr("%1 timetable · %2 classes").arg(schedule.day).arg(count) : qsTr("%1 classes today").arg(count);
                            }
                            color: Colours.palette.m3onTertiaryContainer
                            font: Tokens.font.body.small
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.padding.medium
                StyledText {
                    Layout.fillWidth: true
                    text: root.pages[root.currentPage].title
                    font: Tokens.font.headline.small
                    color: Colours.palette.m3onSurface
                }
                IconButton {
                    icon: "close"
                    type: IconButton.Text
                    onClicked: root.closeRequested()
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.currentPage

                RowLayout {
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        Layout.preferredWidth: 430
                        Layout.fillHeight: true
                        radius: Tokens.rounding.large
                        color: Colours.tPalette.m3surfaceContainerHigh

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.large
                            spacing: Tokens.spacing.medium

                            RowLayout {
                                Layout.fillWidth: true
                                IconButton { icon: "chevron_left"; type: IconButton.Text; onClicked: { if (--root.shownMonth < 0) { root.shownMonth = 11; root.shownYear--; } } }
                                StyledText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: monthGrid.title
                                    color: Colours.palette.m3primary
                                    font: Tokens.font.title.large
                                }
                                IconButton { icon: "chevron_right"; type: IconButton.Text; onClicked: { if (++root.shownMonth > 11) { root.shownMonth = 0; root.shownYear++; } } }
                            }

                            DayOfWeekRow {
                                Layout.fillWidth: true
                                locale: monthGrid.locale
                                delegate: StyledText {
                                    required property var model
                                    horizontalAlignment: Text.AlignHCenter
                                    text: model.shortName
                                    color: (model.day === 0 || model.day === 6) ? Colours.palette.m3tertiary : Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.medium
                                }
                            }

                            MonthGrid {
                                id: monthGrid
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                month: root.shownMonth
                                year: root.shownYear
                                locale: Qt.locale()
                                spacing: 5

                                delegate: StyledRect {
                                    id: dateCell
                                    required property var model
                                    readonly property list<var> events: root.combinedEvents(model.date)
                                    readonly property list<var> calendarEvents: CalendarEvents.eventsForDate(model.date)
                                    readonly property int classLoad: Timetable.loadForDate(model.date)
                                    readonly property bool selected: CalendarEvents.dateKey(model.date) === CalendarEvents.dateKey(root.selectedDate)
                                    implicitHeight: 54
                                    radius: Tokens.rounding.medium
                                    color: selected ? Colours.palette.m3primaryContainer
                                        : model.today ? Colours.palette.m3tertiaryContainer
                                        : classLoad > 0 ? Qt.alpha(Colours.palette.m3tertiaryContainer, 0.12 + classLoad * 0.14)
                                        : "transparent"
                                    opacity: model.month === monthGrid.month ? 1 : 0.38
                                    StateLayer { radius: parent.radius; onClicked: root.selectDate(dateCell.model.date) }
                                    StyledText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top
                                        anchors.topMargin: Tokens.padding.small
                                        text: monthGrid.locale.toString(dateCell.model.day)
                                        color: dateCell.selected ? Colours.palette.m3onPrimaryContainer : dateCell.model.today ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                                        font: Tokens.font.body.medium
                                    }
                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: Tokens.padding.small
                                        spacing: 2
                                        Repeater {
                                            model: {
                                                const categories = [];
                                                for (const event of dateCell.calendarEvents) {
                                                    const value = root.category(event);
                                                    if (!categories.includes(value)) categories.push(value);
                                                }
                                                return categories.slice(0, 3);
                                            }
                                            StyledRect {
                                                required property string modelData
                                                implicitWidth: 4; implicitHeight: 4; radius: 2
                                                color: root.categoryColour(modelData)
                                            }
                                        }
                                    }
                                }
                            }

                            ActionButton {
                                Layout.alignment: Qt.AlignHCenter
                                icon: "today"
                                text: qsTr("Today")
                                onTriggered: root.selectDate(new Date())
                            }
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Tokens.rounding.large
                        color: Colours.tPalette.m3surfaceContainerHigh

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.large
                            contentHeight: details.implicitHeight
                            clip: true

                            ColumnLayout {
                                id: details
                                width: parent.width
                                spacing: Tokens.spacing.medium

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Qt.locale().toString(root.selectedDate, "dddd, d MMMM yyyy")
                                    font: Tokens.font.title.large
                                    color: Colours.palette.m3onSurface
                                    elide: Text.ElideRight
                                }

                                StyledRect {
                                    Layout.fillWidth: true
                                    visible: root.selectedSchedule.adjusted || root.selectedSchedule.noClasses
                                    implicitHeight: adjustmentText.implicitHeight + Tokens.padding.large * 2
                                    radius: Tokens.rounding.large
                                    color: root.selectedSchedule.noClasses ? Colours.palette.m3secondaryContainer : Colours.palette.m3tertiaryContainer
                                    StyledText {
                                        id: adjustmentText
                                        anchors.fill: parent
                                        anchors.margins: Tokens.padding.large
                                        text: root.selectedSchedule.noClasses
                                            ? root.selectedSchedule.reason
                                            : qsTr("%1 timetable is followed instead of %2").arg(root.selectedSchedule.day).arg(root.selectedSchedule.actualDay)
                                        wrapMode: Text.Wrap
                                        color: root.selectedSchedule.noClasses ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onTertiaryContainer
                                        font: Tokens.font.body.medium
                                    }
                                }

                                Repeater {
                                    model: root.selectedEvents
                                    delegate: EventCard {
                                        required property var modelData
                                        eventData: modelData
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: root.selectedEvents.length === 0
                                    Layout.topMargin: Tokens.padding.extraLarge
                                    MaterialIcon { Layout.alignment: Qt.AlignHCenter; text: "event_busy"; color: Colours.palette.m3outline; fontStyle: Tokens.font.icon.large }
                                    StyledText { Layout.alignment: Qt.AlignHCenter; text: qsTr("Nothing scheduled"); color: Colours.palette.m3onSurfaceVariant; font: Tokens.font.body.large }
                                }
                            }
                        }
                    }
                }

                Flickable {
                    contentHeight: timetableGrid.implicitHeight
                    clip: true

                    GridLayout {
                        id: timetableGrid
                        width: parent.width
                        columns: 3
                        rowSpacing: Tokens.spacing.medium
                        columnSpacing: Tokens.spacing.medium

                        Repeater {
                            model: Timetable.dayNames.slice(1)
                            StyledRect {
                                id: dayCard
                                required property string modelData
                                readonly property var entries: Timetable.entriesForDay(modelData)
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                implicitHeight: dayContent.implicitHeight + Tokens.padding.medium * 2
                                radius: Tokens.rounding.large
                                color: modelData === Timetable.dayNames[new Date().getDay()] ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHigh

                                ColumnLayout {
                                    id: dayContent
                                    anchors.fill: parent
                                    anchors.margins: Tokens.padding.medium
                                    spacing: Tokens.spacing.extraSmall
                                    StyledText {
                                        text: dayCard.modelData
                                        color: dayCard.modelData === Timetable.dayNames[new Date().getDay()] ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                                        font: Tokens.font.title.medium
                                    }
                                    Repeater {
                                        model: dayCard.entries
                                        StyledRect {
                                            id: classRow
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: Math.max(42, classContent.implicitHeight + Tokens.padding.extraSmall * 2)
                                            radius: Tokens.rounding.medium
                                            color: Qt.alpha(Colours.palette.m3tertiaryContainer, 0.72)
                                            RowLayout {
                                                id: classContent
                                                anchors.fill: parent
                                                anchors.leftMargin: Tokens.padding.medium
                                                anchors.rightMargin: Tokens.padding.medium
                                                anchors.topMargin: Tokens.padding.extraSmall
                                                anchors.bottomMargin: Tokens.padding.extraSmall
                                                spacing: Tokens.spacing.small
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 0
                                                    StyledText { Layout.fillWidth: true; text: classRow.modelData.course; elide: Text.ElideRight; color: Colours.palette.m3onTertiaryContainer; font: Tokens.font.body.medium }
                                                    StyledText { Layout.fillWidth: true; text: classRow.modelData.room === "TBA" ? classRow.modelData.code : `${classRow.modelData.code} · ${classRow.modelData.room}`; elide: Text.ElideRight; color: Colours.palette.m3onTertiaryContainer; opacity: 0.72; font: Tokens.font.label.small }
                                                }
                                                StyledText { text: `${Timetable.formatTime(classRow.modelData.start)}\n${Timetable.formatTime(classRow.modelData.end)}`; horizontalAlignment: Text.AlignRight; color: Colours.palette.m3onTertiaryContainer; font: Tokens.font.label.small }
                                            }
                                        }
                                    }
                                    Item { Layout.fillHeight: true }
                                    StyledText { visible: dayCard.entries.length === 0; text: qsTr("No classes"); color: Colours.palette.m3outline; font: Tokens.font.body.small }
                                }
                            }
                        }
                    }
                }

                Flickable {
                    contentHeight: settingsColumn.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: settingsColumn
                        width: parent.width
                        spacing: Tokens.spacing.medium

                        SettingsCard {
                            title: qsTr("National holidays")
                            detail: qsTr("Fetch public holidays for %1 and cache them locally").arg(CalendarEvents.countryCode || qsTr("your country"))
                            icon: "celebration"
                            trailing: Component {
                                StyledSwitch {
                                    checked: GlobalConfig.dashboard.showNationalHolidays
                                    onToggled: GlobalConfig.dashboard.showNationalHolidays = checked
                                }
                            }
                        }

                        SettingsCard {
                            title: qsTr("Holiday country")
                            detail: qsTr("Two-letter country code; leave empty for automatic detection")
                            icon: "public"
                            trailing: Component {
                                StyledTextField {
                                    implicitWidth: 64
                                    horizontalAlignment: Text.AlignHCenter
                                    text: GlobalConfig.dashboard.calendarCountryCode
                                    maximumLength: 2
                                    onEditingFinished: GlobalConfig.dashboard.calendarCountryCode = text.trim().toUpperCase()
                                }
                            }
                        }

                        SettingsCard {
                            title: Timetable.loaded ? qsTr("Timetable") : qsTr("No timetable configured")
                            detail: Timetable.loaded ? qsTr("Active %1 to %2 · private local file").arg(Timetable.data.termStart).arg(Timetable.data.termEnd) : Timetable.error
                            icon: "school"
                        }

                        SettingsCard {
                            title: qsTr("Calendar sources")
                            detail: qsTr("%1 personal or subscribed source(s)").arg((GlobalConfig.dashboard.calendarSources ?? []).length)
                            icon: "sync"
                        }

                        RowLayout {
                            spacing: Tokens.spacing.medium
                            ActionButton { icon: "refresh"; text: qsTr("Reload calendars"); onTriggered: CalendarEvents.reload() }
                            ActionButton { icon: "event_repeat"; text: qsTr("Reload timetable"); onTriggered: Timetable.reload() }
                            ActionButton { icon: "folder_open"; text: qsTr("Open timetable file"); onTriggered: Quickshell.execDetached(["xdg-open", Timetable.configPath]) }
                        }
                    }
                }
            }
        }
    }

    component EventCard: StyledRect {
        id: eventCard
        required property var eventData
        Layout.fillWidth: true
        implicitHeight: eventLayout.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainerHighest
        RowLayout {
            id: eventLayout
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.medium
            StyledRect { implicitWidth: 5; Layout.fillHeight: true; radius: 3; color: root.categoryColour(root.category(eventCard.eventData)) }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText { Layout.fillWidth: true; text: String(eventCard.eventData?.title ?? qsTr("Untitled event")); color: Colours.palette.m3onSurface; font: Tokens.font.body.medium; wrapMode: Text.Wrap }
                StyledText {
                    Layout.fillWidth: true
                    text: {
                        const event = eventCard.eventData ?? {};
                        const details = [event.detail, event.source].filter(value => value);
                        return details.join(" · ");
                    }
                    visible: text.length > 0
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }
        }
    }

    component SettingsCard: StyledRect {
        id: setting
        required property string title
        required property string detail
        required property string icon
        property Component trailing: null
        Layout.fillWidth: true
        implicitHeight: 82
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainerHigh
        RowLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium
            MaterialIcon { text: setting.icon; color: Colours.palette.m3primary; fontStyle: Tokens.font.icon.medium }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText { text: setting.title; color: Colours.palette.m3onSurface; font: Tokens.font.body.medium }
                StyledText { Layout.fillWidth: true; text: setting.detail; color: Colours.palette.m3onSurfaceVariant; font: Tokens.font.label.small; wrapMode: Text.Wrap }
            }
            Loader { sourceComponent: setting.trailing; visible: active; active: setting.trailing !== null }
        }
    }

    component ActionButton: StyledRect {
        id: action
        required property string icon
        required property string text
        signal triggered()
        implicitWidth: actionRow.implicitWidth + Tokens.padding.large * 2
        implicitHeight: 42
        radius: Tokens.rounding.full
        color: Colours.palette.m3secondaryContainer
        StateLayer { radius: parent.radius; onClicked: action.triggered() }
        RowLayout {
            id: actionRow
            anchors.centerIn: parent
            spacing: Tokens.spacing.small
            MaterialIcon { text: action.icon; color: Colours.palette.m3onSecondaryContainer; fontStyle: Tokens.font.icon.small }
            StyledText { text: action.text; color: Colours.palette.m3onSecondaryContainer; font: Tokens.font.label.large }
        }
    }
}
