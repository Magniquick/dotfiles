from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MESSAGE_MATH_BLOCK = ROOT / "leftpanel" / "components" / "MessageMathBlock.qml"


def test_math_renderer_uses_same_pixel_size_as_chat_text():
    source = MESSAGE_MATH_BLOCK.read_text()

    assert "readonly property int bodyPixelSize: 13" in source
    assert "font.pixelSize: root.bodyPixelSize" in source
    assert "renderMarkdown(\n      renderRequestId,\n      markdown,\n      cacheRoot,\n      Math.max(120, Math.floor(root.width)),\n      bodyPixelSize," in source
