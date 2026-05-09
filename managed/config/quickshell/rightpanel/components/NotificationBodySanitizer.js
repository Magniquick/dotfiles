.pragma library

function containsWhatsAppLink(text) {
  return String(text || "").match(/<a\s+href="[^"]*web\.whatsapp\.com[^"]*">/i) !== null;
}

function stripWhatsAppHeaderLink(text) {
  if (!containsWhatsAppLink(text))
    return String(text || "");
  return String(text || "").replace(/^<a\s+href="[^"]*">[^<]*<\/a>\n*/i, "");
}

function escapePlainText(text) {
  return String(text || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function normalizeBodyForStyledText(text) {
  const plainText = stripWhatsAppHeaderLink(text).trim().replace(/\r\n?/g, "\n");
  return escapePlainText(plainText).replace(/\n/g, "<br>");
}
