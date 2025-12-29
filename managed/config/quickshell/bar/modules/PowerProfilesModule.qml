import ".."
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

ModuleContainer {
    id: root

    property int profileIndex: root.indexForProfile(PowerProfiles.profile)

    function iconForProfile(profile) {
        if (profile === PowerProfile.Performance)
            return "";

        if (profile === PowerProfile.Balanced)
            return "󰾅";

        if (profile === PowerProfile.PowerSaver)
            return "󰾆";

        return "";
    }
    function indexForProfile(profile) {
        if (profile === PowerProfile.PowerSaver)
            return 0;

        if (profile === PowerProfile.Balanced)
            return 1;

        return 2;
    }
    function profileForIndex(index) {
        if (index <= 0)
            return PowerProfile.PowerSaver;

        if (index === 1)
            return PowerProfile.Balanced;

        return PowerProfile.Performance;
    }
    function profileLabel(profile) {
        if (profile === PowerProfile.Performance)
            return "performance";

        if (profile === PowerProfile.Balanced)
            return "balanced";

        if (profile === PowerProfile.PowerSaver)
            return "power-saver";

        return "unknown";
    }
    function profileTitle(profile) {
        if (profile === PowerProfile.Performance)
            return "Performance";

        if (profile === PowerProfile.Balanced)
            return "Balanced";

        if (profile === PowerProfile.PowerSaver)
            return "Power Saver";

        return "Power profile";
    }
    function setProfile(profile) {
        if (PowerProfiles.profile !== profile)
            PowerProfiles.profile = profile;

        root.profileIndex = root.indexForProfile(profile);
    }
    function syncProfile() {
        root.profileIndex = root.indexForProfile(PowerProfiles.profile);
    }

    tooltipHoverable: true
    tooltipText: ""
    tooltipTitle: "Power profile"

    content: [
        IconLabel {
            text: root.iconForProfile(PowerProfiles.profile)
        }
    ]
    tooltipContent: Component {
        ColumnLayout {
            spacing: Config.space.sm

            TooltipActionsRow {
                ActionChip {
                    active: PowerProfiles.profile === PowerProfile.PowerSaver
                    text: "󰾆"

                    onClicked: root.setProfile(PowerProfile.PowerSaver)
                }
                ActionChip {
                    active: PowerProfiles.profile === PowerProfile.Balanced
                    text: "󰾅"

                    onClicked: root.setProfile(PowerProfile.Balanced)
                }
                ActionChip {
                    active: PowerProfiles.profile === PowerProfile.Performance
                    text: ""

                    onClicked: root.setProfile(PowerProfile.Performance)
                }
            }
        }
    }

    onTooltipActiveChanged: {
        if (root.tooltipActive)
            root.syncProfile();
    }

    Connections {
        function onProfileChanged() {
            root.syncProfile();
        }

        enabled: root.tooltipActive
        target: PowerProfiles
    }
}
