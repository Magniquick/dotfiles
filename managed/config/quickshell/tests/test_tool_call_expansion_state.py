from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT_VIEW = ROOT / "leftpanel" / "components" / "ChatView.qml"
TOOL_ROW = ROOT / "leftpanel" / "components" / "ToolCallRow.qml"


def test_tool_call_expansion_state_lives_in_chat_view():
    chat_view = CHAT_VIEW.read_text()
    tool_row = TOOL_ROW.read_text()

    assert "property var toolExpansionState" in chat_view
    assert "property var toolRawExpansionState" in chat_view
    assert "function toolRowKey(" in chat_view
    assert "function setToolRowExpanded(" in chat_view
    assert "function setToolRowRawExpanded(" in chat_view

    assert "expanded: messageList.toolRowExpanded(" in chat_view
    assert "rawExpanded: messageList.toolRowRawExpanded(" in chat_view
    assert "onExpandedChangeRequested:" in chat_view
    assert "onRawExpandedChangeRequested:" in chat_view

    assert "signal expandedChangeRequested(bool expanded)" in tool_row
    assert "signal rawExpandedChangeRequested(bool expanded)" in tool_row
    assert "root.expanded = !root.expanded" not in tool_row
    assert "root.rawExpanded = !root.rawExpanded" not in tool_row
