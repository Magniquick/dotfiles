pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    visible: false

    property var history: []

    readonly property alias messages: messageModel

    function clearAll() {
        messageModel.clear();
        root.history = [];
    }

    function appendUser(text) {
        messageModel.append({ sender: "user", body: text });
        root.history.push({ role: "user", content: text });
    }

    function appendAssistant(text) {
        messageModel.append({ sender: "assistant", body: text });
        root.history.push({ role: "assistant", content: text });
    }

    // Assistant text that should not be part of the model context.
    function appendAssistantInfo(text) {
        messageModel.append({ sender: "assistant", body: text });
    }

    function deleteMessage(index) {
        if (index < 0 || index >= messageModel.count)
            return;
        const msg = messageModel.get(index);
        const historyIndex = root.history.findIndex(h => {
            return (h.role === "user" && msg.sender === "user" && h.content === msg.body)
                || (h.role === "assistant" && msg.sender === "assistant" && h.content === msg.body);
        });
        if (historyIndex >= 0)
            root.history.splice(historyIndex, 1);
        messageModel.remove(index);
    }

    function editMessage(index, newContent) {
        if (index < 0 || index >= messageModel.count)
            return;
        const msg = messageModel.get(index);
        const historyIndex = root.history.findIndex(h => {
            return (h.role === "user" && msg.sender === "user" && h.content === msg.body)
                || (h.role === "assistant" && msg.sender === "assistant" && h.content === msg.body);
        });
        if (historyIndex >= 0)
            root.history[historyIndex].content = newContent;
        messageModel.setProperty(index, "body", newContent);
    }

    function findPreviousUserIndex(fromIndex) {
        let userMsgIndex = fromIndex - 1;
        while (userMsgIndex >= 0 && messageModel.get(userMsgIndex).sender !== "user")
            userMsgIndex--;
        return userMsgIndex;
    }

    function truncateMessagesFrom(index) {
        while (messageModel.count > index)
            messageModel.remove(messageModel.count - 1);
    }

    function truncateHistoryAfterUserMessage(userBody) {
        const historyIndex = root.history.findIndex(h => h.role === "user" && h.content === userBody);
        if (historyIndex >= 0)
            root.history.splice(historyIndex + 1);
    }

    function resetForModelSwitch(modelId) {
        root.clearAll();
        root.appendAssistantInfo(`Switched to ${modelId}. Chat history cleared.`);
    }

    ListModel {
        id: messageModel

        ListElement {
            sender: "assistant"
            body: "Hi! This panel is wired to OpenAI chat completions."
        }
        ListElement {
            sender: "assistant"
            body: "Set OPENAI_API_KEY to enable replies."
        }
    }
}

