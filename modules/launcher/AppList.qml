pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.launcher.items
import qs.modules.launcher.services

StyledListView {
    id: root

    required property StyledTextField search
    required property DrawerVisibilities visibilities

    model: ScriptModel {
        id: model

        onValuesChanged: root.currentIndex = 0
    }

    spacing: Tokens.spacing.small
    orientation: Qt.Vertical
    implicitHeight: (Tokens.sizes.launcher.itemHeight + spacing) * Math.min(Config.launcher.maxShown, count) - spacing

    preferredHighlightBegin: 0
    preferredHighlightEnd: height
    highlightRangeMode: ListView.ApplyRange

    highlightFollowsCurrentItem: false
    highlight: StyledRect {
        radius: Tokens.rounding.large
        color: Colours.palette.m3onSurface
        opacity: 0.08

        y: root.currentItem?.y ?? 0
        implicitWidth: root.width
        implicitHeight: root.currentItem?.implicitHeight ?? 0

        Behavior on y {
            Anim {}
        }
    }

    state: {
        const text = search.text;
        const prefix = GlobalConfig.launcher.actionPrefix;
        if (text.startsWith(prefix)) {
            for (const action of ["calc", "scheme", "variant"])
                if (text.startsWith(`${prefix}${action} `))
                    return action;

            return "actions";
        }

        return "apps";
    }


    property var currentValues: []

    Timer {
        id: searchDebounce
        interval: 150
        running: false
        repeat: false
        onTriggered: {
            root.updateSearch();
        }
    }

    Connections {
        target: search
        function onTextChanged() {
            searchDebounce.restart();
        }
    }

    Connections {
        target: Apps
        function onSearchResultsChanged() {
            if (root.state === "apps") {
                root.currentValues = Apps.searchResults;
            }
        }
    }

    function updateSearch() {
        if (state === "apps") {
            Apps.search(search.text);
        } else if (state === "actions") {
            currentValues = Actions.query(search.text);
        } else if (state === "calc") {
            currentValues = [0];
        } else if (state === "scheme") {
            currentValues = Schemes.query(search.text);
        } else if (state === "variant") {
            currentValues = M3Variants.query(search.text);
        }
    }

    onStateChanged: {
        if (state === "scheme" || state === "variant")
            Schemes.reload();
        
        // When state changes, immediately update since we might have switched prefix
        searchDebounce.stop();
        updateSearch();
    }


    states: [
        State {
            name: "apps"

            PropertyChanges {
                model.values: root.currentValues
                root.delegate: appItem
            }
        },
        State {
            name: "actions"

            PropertyChanges {
                model.values: root.currentValues
                root.delegate: actionItem
            }
        },
        State {
            name: "calc"

            PropertyChanges {
                model.values: [0]
                root.delegate: calcItem
            }
        },
        State {
            name: "scheme"

            PropertyChanges {
                model.values: root.currentValues
                root.delegate: schemeItem
            }
        },
        State {
            name: "variant"

            PropertyChanges {
                model.values: M3Variants.query(search.text)
                root.delegate: variantItem
            }
        }
    ]

    transitions: Transition {
        SequentialAnimation {
            ParallelAnimation {
                Anim {
                    target: root
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardAccel
                }
                Anim {
                    target: root
                    property: "scale"
                    from: 1
                    to: 0.9
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardAccel
                }
            }
            PropertyAction {
                targets: [model, root]
                properties: "values,delegate"
            }
            ParallelAnimation {
                Anim {
                    target: root
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardDecel
                }
                Anim {
                    target: root
                    property: "scale"
                    from: 0.9
                    to: 1
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardDecel
                }
            }
            PropertyAction {
                targets: [root.add, root.remove]
                property: "enabled"
                value: true
            }
        }
    }

    StyledScrollBar.vertical: StyledScrollBar {
        flickable: root
    }

    add: Transition {
        enabled: !root.state

        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            from: 0
            to: 1
        }
    }

    remove: Transition {
        enabled: !root.state

        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            from: 1
            to: 0
        }
    }

    move: Transition {
        Anim {
            property: "y"
        }
        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            to: 1
        }
    }

    addDisplaced: Transition {
        Anim {
            property: "y"
            type: Anim.StandardSmall
        }
        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            to: 1
        }
    }

    displaced: Transition {
        Anim {
            property: "y"
        }
        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            to: 1
        }
    }

    Component {
        id: appItem

        AppItem {
            visibilities: root.visibilities
        }
    }

    Component {
        id: actionItem

        ActionItem {
            list: root
        }
    }

    Component {
        id: calcItem

        CalcItem {
            list: root
        }
    }

    Component {
        id: schemeItem

        SchemeItem {
            list: root
        }
    }

    Component {
        id: variantItem

        VariantItem {
            list: root
        }
    }
}
