pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import M3Shapes
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

CustomMouseArea {
    id: root

    required property DashboardState dashState

    readonly property int currMonth: dashState.currentDate.getMonth()
    readonly property int currYear: dashState.currentDate.getFullYear()
    property date selectedDate: new Date()
    property date hoveredDate: new Date()
    property Item hoveredDayItem: null

    onCurrYearChanged: CalendarEvents.ensureYear(currYear)

    function onWheel(event: WheelEvent): void {
        if (event.angleDelta.y > 0)
            root.dashState.currentDate = new Date(root.currYear, root.currMonth - 1, 1);
        else if (event.angleDelta.y < 0)
            root.dashState.currentDate = new Date(root.currYear, root.currMonth + 1, 1);
    }

    function popupText(date: date): string {
        const events = CalendarEvents.eventsForDate(date);
        const heading = grid.locale.toString(date, "ddd, d MMMM");
        if (events.length === 0)
            return `${heading}\n${qsTr("No events")}`;

        const labels = events.slice(0, 4).map(event => `• ${event.title}`);
        const remaining = events.length - labels.length;
        if (remaining > 0)
            labels.push(qsTr("+%1 more").arg(remaining));
        return `${heading}\n${labels.join("\n")}`;
    }

    anchors.left: parent.left
    anchors.right: parent.right
    implicitHeight: inner.implicitHeight + inner.anchors.margins * 2

    acceptedButtons: Qt.MiddleButton
    onClicked: root.dashState.currentDate = new Date()

    ColumnLayout {
        id: inner

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.extraSmall

        RowLayout {
            id: monthNavigationRow

            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            IconButton {
                icon: "chevron_left"
                type: IconButton.Text
                font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                padding: Tokens.padding.small
                onClicked: root.dashState.currentDate = new Date(root.currYear, root.currMonth - 1, 1)
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                implicitWidth: monthYearDisplay.implicitWidth + Tokens.padding.large * 2
                implicitHeight: monthYearDisplay.implicitHeight + Tokens.padding.extraSmall * 2

                StateLayer {
                    color: Colours.palette.m3primary
                    radius: pressed ? Tokens.rounding.small : Tokens.rounding.large
                    disabled: {
                        const now = new Date();
                        return root.currMonth === now.getMonth() && root.currYear === now.getFullYear();
                    }
                    onClicked: root.dashState.currentDate = new Date()

                    Behavior on radius {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                StyledText {
                    id: monthYearDisplay

                    anchors.centerIn: parent
                    text: grid.title
                    color: Colours.palette.m3primary
                    font: Tokens.font.title.builders.small.capitalisation(Font.Capitalize).build()
                }
            }

            IconButton {
                icon: "chevron_right"
                type: IconButton.Text
                font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                padding: Tokens.padding.small
                onClicked: root.dashState.currentDate = new Date(root.currYear, root.currMonth + 1, 1)
            }
        }

        DayOfWeekRow {
            id: daysRow

            Layout.fillWidth: true
            locale: grid.locale

            delegate: StyledText {
                required property var model

                horizontalAlignment: Text.AlignHCenter
                text: model.shortName
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                color: (model.day === 0 || model.day === 6) ? Colours.palette.m3tertiary : Colours.palette.m3onSurface
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: grid.implicitHeight

            MonthGrid {
                id: grid

                month: root.currMonth
                year: root.currYear

                anchors.fill: parent

                spacing: 3
                locale: Qt.locale()

                delegate: Item {
                    id: dayItem

                    required property var model
                    readonly property int load: CalendarEvents.eventLoadForDate(model.date)
                    readonly property bool holiday: CalendarEvents.holidaysForDate(model.date).length > 0
                    readonly property bool hasCalendarEvent: CalendarEvents.eventsForDate(model.date).some(event => !event.holiday)
                    readonly property bool selected: CalendarEvents.dateKey(model.date) === CalendarEvents.dateKey(root.selectedDate)
                    readonly property bool hovered: dayHover.containsMouse

                    implicitWidth: implicitHeight
                    implicitHeight: text.implicitHeight + Tokens.padding.medium

                    StyledRect {
                        anchors.centerIn: parent
                        implicitWidth: Math.max(text.implicitWidth, text.implicitHeight) + Tokens.padding.small
                        implicitHeight: implicitWidth
                        radius: width / 2
                        color: Colours.palette.m3primary
                        opacity: dayItem.selected && !dayItem.model.today ? 0.14 : 0
                    }

                    StyledText {
                        id: text

                        anchors.centerIn: parent

                        horizontalAlignment: Text.AlignHCenter
                        text: grid.locale.toString(dayItem.model.day)
                        color: {
                            const dayOfWeek = dayItem.model.date.getDay();
                            if (dayOfWeek === 0 || dayOfWeek === 6)
                                return Colours.palette.m3tertiary;

                            return Colours.palette.m3onSurfaceVariant;
                        }
                        opacity: dayItem.model.today || dayItem.model.month === grid.month ? 1 : 0.4
                        font: Tokens.font.body.small
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        spacing: 2

                        Repeater {
                            model: dayItem.load

                            StyledRect {
                                required property int index

                                implicitWidth: 3
                                implicitHeight: 3
                                radius: 2
                                color: Colours.palette.m3primary
                                opacity: 0.45 + index * 0.22
                            }
                        }

                        StyledRect {
                            visible: dayItem.holiday
                            implicitWidth: 3
                            implicitHeight: 3
                            radius: 2
                            color: Colours.palette.m3tertiary
                        }

                        StyledRect {
                            visible: dayItem.hasCalendarEvent && dayItem.load === 0
                            implicitWidth: 3
                            implicitHeight: 3
                            radius: 2
                            color: Colours.palette.m3primary
                        }
                    }

                    MouseArea {
                        id: dayHover

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.ArrowCursor
                        onEntered: {
                            root.selectedDate = dayItem.model.date;
                            root.hoveredDate = dayItem.model.date;
                            root.hoveredDayItem = dayItem;
                            dayPopup.showTimer.restart();
                        }
                        onExited: {
                            dayPopup.showTimer.stop();
                            if (root.hoveredDayItem === dayItem) {
                                dayPopup.tooltipVisible = false;
                                root.hoveredDayItem = null;
                            }
                        }
                        onClicked: root.selectedDate = dayItem.model.date
                    }
                }
            }

            Tooltip {
                id: dayPopup

                target: root.hoveredDayItem ?? grid
                text: root.popupText(root.hoveredDate)
                delay: 120
            }

            MaterialShape {
                id: todayIndicator

                readonly property Item todayItem: grid.contentItem.children.find(c => c.model.today) ?? null
                property Item today

                onTodayItemChanged: {
                    if (todayItem)
                        today = todayItem;
                }

                x: today ? today.x + (today.width - implicitWidth) / 2 : 0
                y: today ? today.y - Tokens.padding.extraSmall - 1 : 0

                implicitSize: today ? Math.max(today.implicitWidth, today.implicitHeight) + Tokens.padding.extraSmall * 2 : 0
                shape: MaterialShape.Sunny

                clip: true
                color: Colours.palette.m3primary

                opacity: todayItem ? 1 : 0
                scale: todayItem ? 1 : 0.7

                Colouriser {
                    x: -todayIndicator.x
                    y: -todayIndicator.y

                    implicitWidth: grid.width
                    implicitHeight: grid.height

                    source: grid
                    sourceColor: Colours.palette.m3onSurface
                    colorizationColor: Colours.palette.m3onPrimary
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                Behavior on x {
                    Anim {}
                }

                Behavior on y {
                    Anim {}
                }
            }
        }

    }
}
