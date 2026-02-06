pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

Item {
    id: root
    visible: false

    property url configFileUrl: Qt.resolvedUrl("../config.json")

    FileView {
        id: configFile
        path: root.configFileUrl
        blockLoading: true
    }

    readonly property var moodsData: {
        try {
            return JSON.parse(configFile.text()).moods || [];
        } catch (e) {
            return [];
        }
    }

    readonly property var availableMoods: moodsData.map(m => ({
        value: m.name.toLowerCase(),
        label: m.name,
        icon: m.icon || "\uf4ff",
        description: m.subtext || ""
    }))

    readonly property var moodPrompts: {
        const prompts = {};
        for (const m of moodsData)
            prompts[m.name.toLowerCase()] = m.prompt;
        return prompts;
    }

    readonly property var moodModels: {
        const models = {};
        for (const m of moodsData) {
            if (m.default_model)
                models[m.name.toLowerCase()] = m.default_model;
        }
        return models;
    }

    function moodIcon(moodId) {
        const key = (moodId || "").toLowerCase();
        const mood = moodsData.find(m => m.name.toLowerCase() === key);
        return mood ? (mood.icon || "\uf4c4") : "\uf4c4";
    }

    function moodName(moodId) {
        const key = (moodId || "").toLowerCase();
        const mood = moodsData.find(m => m.name.toLowerCase() === key);
        return mood ? (mood.name || "Assistant") : "Assistant";
    }
}

