#include "MathRenderer.h"

#include <QColor>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMetaObject>
#include <QPointer>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTextCharFormat>
#include <QTextCursor>
#include <QTextDocument>
#include <QUrl>
#include <QXmlStreamReader>
#include <QtConcurrent/QtConcurrent>
#include <QtMath>

#include <algorithm>
#include <mutex>
#include <vector>

namespace {

struct Segment {
  enum class Type {
    Text,
    InlineMath,
    DisplayMath,
  };

  Type type = Type::Text;
  QString text;
  QString placeholder;
};

struct RenderedMath {
  QString placeholder;
  QString html;
};

struct RenderedSize {
  qreal logicalWidth = 0;
  qreal logicalHeight = 0;
  qreal physicalWidth = 0;
  qreal physicalHeight = 0;
};

std::mutex ratexMutex;

auto formulaHash(const QString& formula, Segment::Type type, const QString& rendererCacheKey,
                 int maxWidth, qreal textSize, qreal padding, const QColor& color,
                 qreal renderScale) -> QString {
  QCryptographicHash hash(QCryptographicHash::Sha256);
  hash.addData(rendererCacheKey.toUtf8());
  hash.addData(formula.toUtf8());
  hash.addData(type == Segment::Type::InlineMath ? QByteArrayLiteral("inline")
                                                 : QByteArrayLiteral("display"));
  hash.addData(QByteArray::number(maxWidth));
  hash.addData(QByteArray::number(textSize, 'f', 2));
  hash.addData(QByteArray::number(padding, 'f', 2));
  hash.addData(color.name(QColor::HexArgb).toUtf8());
  hash.addData(QByteArray::number(renderScale, 'f', 2));
  return QString::fromLatin1(hash.result().toHex());
}

auto startsWithAt(const QString& text, int offset, const QString& needle) -> bool {
  return offset >= 0 && offset + needle.size() <= text.size() &&
         text.mid(offset, needle.size()) == needle;
}

auto findClosingDollar(const QString& text, int offset, const QString& delimiter) -> int {
  int i = offset;
  while (i < text.size()) {
    const int found = text.indexOf(delimiter, i);
    if (found < 0) {
      return -1;
    }
    if (found == 0 || text.at(found - 1) != QChar('\\')) {
      return found;
    }
    i = found + delimiter.size();
  }
  return -1;
}

auto captureEnvironment(const QString& text, int offset) -> QString {
  static const QRegularExpression envStart(
      R"(\\begin\{(equation\*?|align\*?|gather\*?|multline\*?|matrix\*?|bmatrix|pmatrix|vmatrix|Vmatrix)\})");
  const QRegularExpressionMatch match = envStart.match(
      text, offset, QRegularExpression::NormalMatch, QRegularExpression::AnchorAtOffsetMatchOption);
  if (!match.hasMatch()) {
    return {};
  }

  const QString envName = match.captured(1);
  const QString endToken = QStringLiteral("\\end{%1}").arg(envName);
  const int endIndex = text.indexOf(endToken, match.capturedEnd());
  if (endIndex < 0) {
    return {};
  }
  return text.mid(offset, endIndex + endToken.size() - offset);
}

auto tokenizeMarkdown(const QString& source) -> std::vector<Segment> {
  std::vector<Segment> segments;
  QString textBuffer;

  auto flushText = [&]() -> void {
    if (textBuffer.isEmpty()) {
      return;
    }
    segments.push_back({.type = Segment::Type::Text, .text = textBuffer, .placeholder = {}});
    textBuffer.clear();
  };

  int i = 0;
  int placeholderIndex = 0;

  while (i < source.size()) {
    if (source.at(i) == QChar('`')) {
      int run = 1;
      while (i + run < source.size() && source.at(i + run) == QChar('`')) {
        ++run;
      }
      const QString fence(run, QChar('`'));
      const int closeIndex = source.indexOf(fence, i + run);
      if (closeIndex < 0) {
        textBuffer += source.mid(i);
        break;
      }
      textBuffer += source.mid(i, closeIndex + run - i);
      i = closeIndex + run;
      continue;
    }

    const QString environment = captureEnvironment(source, i);
    if (!environment.isEmpty()) {
      flushText();
      segments.push_back({.type = Segment::Type::DisplayMath,
                          .text = environment,
                          .placeholder = QStringLiteral("@@MATH_%1@@").arg(placeholderIndex++)});
      i += environment.size();
      continue;
    }

    if (startsWithAt(source, i, QStringLiteral("\\["))) {
      const int closeIndex = source.indexOf(QStringLiteral("\\]"), i + 2);
      if (closeIndex >= 0) {
        flushText();
        segments.push_back({.type = Segment::Type::DisplayMath,
                            .text = source.mid(i, closeIndex + 2 - i),
                            .placeholder = QStringLiteral("@@MATH_%1@@").arg(placeholderIndex++)});
        i = closeIndex + 2;
        continue;
      }
    }

    if (startsWithAt(source, i, QStringLiteral("$$"))) {
      const int closeIndex = findClosingDollar(source, i + 2, QStringLiteral("$$"));
      if (closeIndex >= 0) {
        flushText();
        segments.push_back({.type = Segment::Type::DisplayMath,
                            .text = source.mid(i, closeIndex + 2 - i),
                            .placeholder = QStringLiteral("@@MATH_%1@@").arg(placeholderIndex++)});
        i = closeIndex + 2;
        continue;
      }
    }

    if (startsWithAt(source, i, QStringLiteral("\\("))) {
      const int closeIndex = source.indexOf(QStringLiteral("\\)"), i + 2);
      if (closeIndex >= 0) {
        flushText();
        segments.push_back({.type = Segment::Type::InlineMath,
                            .text = source.mid(i, closeIndex + 2 - i),
                            .placeholder = QStringLiteral("@@MATH_%1@@").arg(placeholderIndex++)});
        i = closeIndex + 2;
        continue;
      }
    }

    if (source.at(i) == QChar('$') && (i == 0 || source.at(i - 1) != QChar('\\'))) {
      const int closeIndex = findClosingDollar(source, i + 1, QStringLiteral("$"));
      if (closeIndex > i + 1) {
        flushText();
        segments.push_back({.type = Segment::Type::InlineMath,
                            .text = source.mid(i, closeIndex + 1 - i),
                            .placeholder = QStringLiteral("@@MATH_%1@@").arg(placeholderIndex++)});
        i = closeIndex + 1;
        continue;
      }
    }

    textBuffer += source.at(i);
    ++i;
  }

  flushText();
  return segments;
}

auto stripMathDelimiters(QString formula) -> QString {
  formula = formula.trimmed();

  auto stripPair = [&](const QString& left, const QString& right) -> bool {
    if (!formula.startsWith(left) || !formula.endsWith(right) ||
        formula.size() < left.size() + right.size()) {
      return false;
    }
    formula = formula.mid(left.size(), formula.size() - left.size() - right.size()).trimmed();
    return true;
  };

  stripPair(QStringLiteral("$$"), QStringLiteral("$$")) ||
      stripPair(QStringLiteral("$"), QStringLiteral("$")) ||
      stripPair(QStringLiteral("\\("), QStringLiteral("\\)")) ||
      stripPair(QStringLiteral("\\["), QStringLiteral("\\]"));

  return formula;
}

auto formulaForRatex(const Segment& segment) -> QString {
  QString formula = stripMathDelimiters(segment.text);
  if (segment.type == Segment::Type::DisplayMath) {
    formula.replace(QRegularExpression(QStringLiteral(R"(\s+)")), QStringLiteral(" "));
    formula = formula.trimmed();
  }
  return formula;
}

auto markdownWithPlaceholders(const std::vector<Segment>& segments) -> QString {
  QString result;
  for (const Segment& segment : segments) {
    if (segment.type == Segment::Type::Text) {
      result += segment.text;
      continue;
    }

    if (segment.type == Segment::Type::DisplayMath) {
      if (!result.endsWith('\n')) {
        result += '\n';
      }
      result += segment.placeholder;
      if (!result.endsWith('\n')) {
        result += '\n';
      }
    } else {
      result += segment.placeholder;
    }
  }
  return result;
}

auto ratexExecutable() -> QString {
#ifdef QSMATH_RENDERER_PATH
  const QString bundled = QString::fromUtf8(QSMATH_RENDERER_PATH);
  if (QFile::exists(bundled)) {
    return bundled;
  }
#endif

  const QString bundledFromPath =
      QStandardPaths::findExecutable(QStringLiteral("qsmath-render-svg"));
  if (!bundledFromPath.isEmpty()) {
    return bundledFromPath;
  }

  return {};
}

auto ratexCacheKey(const QString& executable) -> QString {
  QFileInfo const info(executable);
  const QString path =
      info.canonicalFilePath().isEmpty() ? info.absoluteFilePath() : info.canonicalFilePath();

  return QStringLiteral("ratex-svg:%1:%2:%3")
      .arg(path)
      .arg(info.size())
      .arg(info.lastModified().toMSecsSinceEpoch());
}

auto parseSvgLength(const QString& text, qreal* value) -> bool {
  if (value == nullptr) {
    return false;
  }

  const QString trimmed = text.trimmed();
  if (trimmed.isEmpty() || trimmed.endsWith(QLatin1Char('%'))) {
    return false;
  }

  qsizetype end = 0;
  while (end < trimmed.size()) {
    const QChar ch = trimmed.at(end);
    if (!(ch.isDigit() || ch == QLatin1Char('.') || ch == QLatin1Char('-') ||
          ch == QLatin1Char('+') || ch == QLatin1Char('e') || ch == QLatin1Char('E'))) {
      break;
    }
    ++end;
  }

  if (end <= 0) {
    return false;
  }

  bool ok = false;
  const qreal parsed = trimmed.left(end).toDouble(&ok);
  if (!ok || parsed <= 0) {
    return false;
  }

  *value = parsed;
  return true;
}

auto parseSvgViewBox(const QString& viewBox, qreal* width, qreal* height) -> bool {
  const QStringList parts = QString(viewBox)
                                .replace(QLatin1Char(','), QLatin1Char(' '))
                                .split(QLatin1Char(' '), Qt::SkipEmptyParts);
  if (parts.size() != 4) {
    return false;
  }

  bool widthOk = false;
  bool heightOk = false;
  const qreal parsedWidth = parts.at(2).toDouble(&widthOk);
  const qreal parsedHeight = parts.at(3).toDouble(&heightOk);
  if (!widthOk || !heightOk || parsedWidth <= 0 || parsedHeight <= 0) {
    return false;
  }

  if (width != nullptr) {
    *width = parsedWidth;
  }
  if (height != nullptr) {
    *height = parsedHeight;
  }
  return true;
}

auto parseSvgSize(const QString& svgPath, qreal scale, RenderedSize* size) -> bool {
  if ((size == nullptr) || scale <= 0) {
    return false;
  }

  QFile svg(svgPath);
  if (!svg.open(QIODevice::ReadOnly | QIODevice::Text)) {
    return false;
  }

  QXmlStreamReader xml(&svg);
  while (!xml.atEnd()) {
    xml.readNext();
    if (!xml.isStartElement()) {
      continue;
    }
    if (xml.name() != QLatin1String("svg")) {
      return false;
    }

    const QXmlStreamAttributes attributes = xml.attributes();
    qreal physicalWidth = 0;
    qreal physicalHeight = 0;
    const bool hasWidth =
        parseSvgLength(attributes.value(QStringLiteral("width")).toString(), &physicalWidth);
    const bool hasHeight =
        parseSvgLength(attributes.value(QStringLiteral("height")).toString(), &physicalHeight);

    if ((!hasWidth || !hasHeight) &&
        !parseSvgViewBox(attributes.value(QStringLiteral("viewBox")).toString(), &physicalWidth,
                         &physicalHeight)) {
      return false;
    }

    size->physicalWidth = physicalWidth;
    size->physicalHeight = physicalHeight;
    size->logicalWidth = size->physicalWidth / scale;
    size->logicalHeight = size->physicalHeight / scale;
    return true;
  }

  return false;
}

auto normalizeSvgPaintValues(QString svg) -> QString {
  static const QRegularExpression rgbaPattern(
      R"regex((\b(?:fill|stroke)=")rgba\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(?:1(?:\.0+)?|0?\.\d+)\s*\)("))regex");

  qsizetype offset = 0;
  QString normalized;
  QRegularExpressionMatch match;

  while ((match = rgbaPattern.match(svg, offset)).hasMatch()) {
    normalized += svg.mid(offset, match.capturedStart() - offset);

    const int red = std::clamp(match.captured(2).toInt(), 0, 255);
    const int green = std::clamp(match.captured(3).toInt(), 0, 255);
    const int blue = std::clamp(match.captured(4).toInt(), 0, 255);
    const QString hex = QColor(red, green, blue).name(QColor::HexRgb);
    normalized += match.captured(1) + hex + match.captured(5);

    offset = match.capturedEnd();
  }

  if (offset == 0) {
    return svg;
  }

  normalized += svg.mid(offset);
  return normalized;
}

auto copyRenderedSvg(const QString& sourcePath, const QString& targetPath, QString* error) -> bool {
  QFile::remove(targetPath);

  QFile source(sourcePath);
  if (!source.open(QIODevice::ReadOnly | QIODevice::Text)) {
    if (error != nullptr) {
      *error = QStringLiteral("Failed to read rendered SVG: %1").arg(sourcePath);
    }
    return false;
  }

  QFile target(targetPath);
  if (target.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate)) {
    target.write(normalizeSvgPaintValues(QString::fromUtf8(source.readAll())).toUtf8());
    return true;
  }

  if (error != nullptr) {
    *error = QStringLiteral("Failed to write rendered SVG to cache: %1").arg(targetPath);
  }
  return false;
}

auto renderFormulaWithRatex(const Segment& segment, const QString& svgPath, qreal textSize,
                            qreal padding, const QColor& foreground, qreal renderScale,
                            const QString& executable, QString* error) -> bool {
  QTemporaryDir const outputDir(QDir::tempPath() + QStringLiteral("/qsmath-ratex-XXXXXX"));
  if (!outputDir.isValid()) {
    if (error != nullptr) {
      *error = QStringLiteral("Failed to create temporary RaTeX output directory");
    }
    return false;
  }

  QStringList arguments{
      QStringLiteral("--output-dir"), outputDir.path(),
      QStringLiteral("--font-size"),  QString::number(textSize, 'f', 2),
      QStringLiteral("--dpr"),        QString::number(renderScale, 'f', 2),
      QStringLiteral("--color"),      foreground.name(QColor::HexRgb),
  };
  if (segment.type == Segment::Type::InlineMath) {
    arguments.prepend(QStringLiteral("--inline"));
    arguments.append(QStringLiteral("--padding"));
    arguments.append(QStringLiteral("0"));
  } else {
    arguments.append(QStringLiteral("--padding"));
    arguments.append(QString::number(padding, 'f', 2));
  }

  QProcess process;
  process.setProgram(executable);
  process.setArguments(arguments);
  process.start();
  if (!process.waitForStarted(3000)) {
    if (error != nullptr) {
      *error = QStringLiteral("Failed to start %1: %2").arg(executable, process.errorString());
    }
    return false;
  }

  process.write(formulaForRatex(segment).toUtf8());
  process.write("\n");
  process.closeWriteChannel();

  if (!process.waitForFinished(10000)) {
    process.kill();
    process.waitForFinished(1000);
    if (error != nullptr) {
      *error = QStringLiteral("RaTeX render timed out");
    }
    return false;
  }

  const QString stdoutText = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
  const QString stderrText = QString::fromUtf8(process.readAllStandardError()).trimmed();
  const QString renderedPath = outputDir.filePath(QStringLiteral("0001.svg"));

  if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0 ||
      !QFile::exists(renderedPath)) {
    if (error != nullptr) {
      const QString detail = !stderrText.isEmpty() ? stderrText : stdoutText;
      *error = detail.isEmpty() ? QStringLiteral("RaTeX render failed")
                                : QStringLiteral("RaTeX render failed: %1").arg(detail);
    }
    return false;
  }

  return copyRenderedSvg(renderedPath, svgPath, error);
}

auto renderSegment(const Segment& segment, const QString& cacheDir, int maxWidth, qreal textSize,
                   qreal padding, const QColor& foreground, qreal renderScale, QString* error)
    -> RenderedMath {
  const QString executable = ratexExecutable();
  if (executable.isEmpty()) {
    if (error != nullptr) {
      *error =
          QStringLiteral("qsmath-render-svg not found; rebuild qsmath with tools/build-qsmath.sh");
    }
    return {};
  }

  const qreal scale = std::max<qreal>(1.0, renderScale);
  const QString formula = formulaForRatex(segment);
  const QString svgPath = cacheDir + QLatin1Char('/') +
                          formulaHash(formula, segment.type, ratexCacheKey(executable), maxWidth,
                                      textSize, padding, foreground, scale) +
                          QStringLiteral(".svg");

  RenderedSize size;

  if (!QFile::exists(svgPath)) {
    if (!renderFormulaWithRatex(segment, svgPath, textSize, padding, foreground, scale, executable,
                                error)) {
      return {};
    }
  }

  parseSvgSize(svgPath, scale, &size);

  const QString url = QUrl::fromLocalFile(svgPath).toString().toHtmlEscaped();
  QString attrs = QStringLiteral("src=\"%1\"").arg(url);
  if (size.logicalWidth > 0 && size.logicalHeight > 0) {
    attrs += QStringLiteral(" width=\"%1\" height=\"%2\"")
                 .arg(qCeil(size.logicalWidth))
                 .arg(qCeil(size.logicalHeight));
  }
  if (segment.type == Segment::Type::InlineMath) {
    attrs += QStringLiteral(" align=\"middle\"");
  } else {
    attrs += QStringLiteral(" style=\"display:block; margin:0.5em auto; max-width:100%;\"");
  }

  return {.placeholder = segment.placeholder, .html = QStringLiteral("<img %1 />").arg(attrs)};
}

auto injectRenderedMath(QString html, const std::vector<RenderedMath>& rendered) -> QString {
  for (const RenderedMath& entry : rendered) {
    const QRegularExpression blockPattern(QStringLiteral(R"(<p[^>]*>\s*%1\s*</p>)")
                                              .arg(QRegularExpression::escape(entry.placeholder)));
    html.replace(blockPattern,
                 QStringLiteral("<div style=\"text-align:center; margin:0.25em 0;\">%1</div>")
                     .arg(entry.html));
    html.replace(entry.placeholder.toHtmlEscaped(), entry.html);
    html.replace(entry.placeholder, entry.html);
  }
  return html;
}

auto renderMarkdownToHtml(const QString& markdown, const QString& cacheDir, int maxWidth,
                          qreal textSize, qreal padding, const QColor& foreground,
                          qreal renderScale, QString* error) -> QString {
  if (!QDir().mkpath(cacheDir)) {
    if (error != nullptr) {
      *error = QStringLiteral("Failed to create cache directory: %1").arg(cacheDir);
    }
    return {};
  }

  const std::vector<Segment> segments = tokenizeMarkdown(markdown);
  const QString placeholderMarkdown = markdownWithPlaceholders(segments);

  QTextDocument document;
  document.setMarkdown(placeholderMarkdown);
  QTextCursor cursor(&document);
  cursor.select(QTextCursor::Document);
  QTextCharFormat textFormat;
  textFormat.setForeground(foreground);
  cursor.mergeCharFormat(textFormat);
  QString const html = document.toHtml();

  std::vector<RenderedMath> rendered;
  rendered.reserve(segments.size());

  std::scoped_lock const lock(ratexMutex);
  for (const Segment& segment : segments) {
    if (segment.type == Segment::Type::Text) {
      continue;
    }
    RenderedMath const math = renderSegment(segment, cacheDir, maxWidth, textSize, padding,
                                            foreground, renderScale, error);
    if ((error != nullptr) && !error->isEmpty()) {
      return {};
    }
    rendered.push_back(math);
  }

  return injectRenderedMath(html, rendered);
}

} // namespace

MathRenderer::MathRenderer(QObject* parent) : QObject(parent) {}

void MathRenderer::renderMarkdown(const QString& requestId, const QString& markdown,
                                  const QString& cacheDir, int maxWidth, qreal textSize,
                                  qreal padding, const QString& foreground, qreal renderScale) {
  QPointer<MathRenderer> const self(this);
  (void)QtConcurrent::run([self, requestId, markdown, cacheDir, maxWidth, textSize, padding,
                           foreground, renderScale]() -> void {
    const QColor color(foreground);
    const QColor resolvedColor = color.isValid() ? color : QColor(QStringLiteral("#000000"));
    const qreal resolvedScale = std::clamp<qreal>(renderScale, 1.0, 4.0);
    QString error;
    const QString html = renderMarkdownToHtml(
        markdown, cacheDir, std::max(120, maxWidth), textSize > 0 ? textSize : 18.0,
        padding >= 0 ? padding : 4.0, resolvedColor, resolvedScale, &error);

    if (!self) {
      return;
    }

    if (!error.isEmpty()) {
      QMetaObject::invokeMethod(
          self,
          [self, requestId, error]() -> void {
            if (self) {
              self->requestFailed(requestId, error);
            }
          },
          Qt::QueuedConnection);
      return;
    }

    QMetaObject::invokeMethod(
        self,
        [self, requestId, html]() -> void {
          if (self) {
            self->requestFinished(requestId, html);
          }
        },
        Qt::QueuedConnection);
  });
}
