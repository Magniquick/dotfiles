#include "MathRenderer.h"

#include <QColor>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QMetaObject>
#include <QPointer>
#include <QRegularExpression>
#include <QTextDocument>
#include <QUrl>
#include <QtMath>
#include <QtConcurrent/QtConcurrent>

#include <cairomm/context.h>
#include <cairomm/surface.h>

#ifdef Q_FOREACH
#undef Q_FOREACH
#endif
#ifdef emit
#undef emit
#endif
#ifdef slots
#undef slots
#endif
#ifdef signals
#undef signals
#endif

#include <latex.h>
#include <platform/cairo/graphic_cairo.h>

#include <algorithm>
#include <memory>
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

std::mutex latexMutex;
std::once_flag latexInitOnce;
QString latexInitError;

tex::color toTexColor(const QColor& color) {
  return ((color.alpha() & 0xff) << 24) | ((color.red() & 0xff) << 16) |
         ((color.green() & 0xff) << 8) | (color.blue() & 0xff);
}

QString formulaHash(const QString& formula, int maxWidth, const QColor& color, qreal renderScale) {
  QCryptographicHash hash(QCryptographicHash::Sha256);
  hash.addData(formula.toUtf8());
  hash.addData(QByteArray::number(maxWidth));
  hash.addData(color.name(QColor::HexArgb).toUtf8());
  hash.addData(QByteArray::number(renderScale, 'f', 2));
  return QString::fromLatin1(hash.result().toHex());
}

bool startsWithAt(const QString& text, int offset, const QString& needle) {
  return offset >= 0 && offset + needle.size() <= text.size() &&
         text.mid(offset, needle.size()) == needle;
}

int findClosingDollar(const QString& text, int offset, const QString& delimiter) {
  int i = offset;
  while (i < text.size()) {
    const int found = text.indexOf(delimiter, i);
    if (found < 0)
      return -1;
    if (found == 0 || text.at(found - 1) != QChar('\\'))
      return found;
    i = found + delimiter.size();
  }
  return -1;
}

QString captureEnvironment(const QString& text, int offset) {
  static const QRegularExpression envStart(
      R"(\\begin\{(equation\*?|align\*?|gather\*?|multline\*?|matrix\*?|bmatrix|pmatrix|vmatrix|Vmatrix)\})");
  const QRegularExpressionMatch match = envStart.match(
      text, offset, QRegularExpression::NormalMatch, QRegularExpression::AnchorAtOffsetMatchOption);
  if (!match.hasMatch())
    return {};

  const QString envName = match.captured(1);
  const QString endToken = QStringLiteral("\\end{%1}").arg(envName);
  const int endIndex = text.indexOf(endToken, match.capturedEnd());
  if (endIndex < 0)
    return {};
  return text.mid(offset, endIndex + endToken.size() - offset);
}

std::vector<Segment> tokenizeMarkdown(const QString& source) {
  std::vector<Segment> segments;
  QString textBuffer;

  auto flushText = [&]() {
    if (textBuffer.isEmpty())
      return;
    segments.push_back({Segment::Type::Text, textBuffer, {}});
    textBuffer.clear();
  };

  int i = 0;
  int placeholderIndex = 0;

  while (i < source.size()) {
    if (source.at(i) == QChar('`')) {
      int run = 1;
      while (i + run < source.size() && source.at(i + run) == QChar('`'))
        ++run;
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
      segments.push_back({Segment::Type::DisplayMath, environment,
                          QStringLiteral("@@MATH_%1@@").arg(placeholderIndex++)});
      i += environment.size();
      continue;
    }

    if (startsWithAt(source, i, QStringLiteral("\\["))) {
      const int closeIndex = source.indexOf(QStringLiteral("\\]"), i + 2);
      if (closeIndex >= 0) {
        flushText();
        segments.push_back({Segment::Type::DisplayMath, source.mid(i, closeIndex + 2 - i),
                            QStringLiteral("@@MATH_%1@@").arg(placeholderIndex++)});
        i = closeIndex + 2;
        continue;
      }
    }

    if (startsWithAt(source, i, QStringLiteral("$$"))) {
      const int closeIndex = findClosingDollar(source, i + 2, QStringLiteral("$$"));
      if (closeIndex >= 0) {
        flushText();
        segments.push_back({Segment::Type::DisplayMath, source.mid(i, closeIndex + 2 - i),
                            QStringLiteral("@@MATH_%1@@").arg(placeholderIndex++)});
        i = closeIndex + 2;
        continue;
      }
    }

    if (startsWithAt(source, i, QStringLiteral("\\("))) {
      const int closeIndex = source.indexOf(QStringLiteral("\\)"), i + 2);
      if (closeIndex >= 0) {
        flushText();
        segments.push_back({Segment::Type::InlineMath, source.mid(i, closeIndex + 2 - i),
                            QStringLiteral("@@MATH_%1@@").arg(placeholderIndex++)});
        i = closeIndex + 2;
        continue;
      }
    }

    if (source.at(i) == QChar('$') && (i == 0 || source.at(i - 1) != QChar('\\'))) {
      const int closeIndex = findClosingDollar(source, i + 1, QStringLiteral("$"));
      if (closeIndex > i + 1) {
        flushText();
        segments.push_back({Segment::Type::InlineMath, source.mid(i, closeIndex + 1 - i),
                            QStringLiteral("@@MATH_%1@@").arg(placeholderIndex++)});
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

QString markdownWithPlaceholders(const std::vector<Segment>& segments) {
  QString result;
  for (const Segment& segment : segments) {
    if (segment.type == Segment::Type::Text) {
      result += segment.text;
      continue;
    }

    if (segment.type == Segment::Type::DisplayMath) {
      if (!result.endsWith('\n'))
        result += '\n';
      result += segment.placeholder;
      if (!result.endsWith('\n'))
        result += '\n';
    } else {
      result += segment.placeholder;
    }
  }
  return result;
}

RenderedMath renderSegment(const Segment& segment, const QString& cacheDir, int maxWidth,
                           qreal textSize, qreal padding, const QColor& foreground,
                           qreal renderScale) {
  const qreal scale = std::max<qreal>(1.0, renderScale);
  const QString svgPath = cacheDir + QLatin1Char('/') +
                          formulaHash(segment.text, maxWidth, foreground, scale) +
                          QStringLiteral(".svg");

  RenderedSize size;

  if (!QFile::exists(svgPath)) {
    std::unique_ptr<tex::TeXRender> render(tex::LaTeX::parse(
        segment.text.toStdWString(), qRound(maxWidth * scale), static_cast<float>(textSize * scale),
        static_cast<float>((textSize * scale) / 3.0), toTexColor(foreground)));

    size.physicalWidth = render->getWidth() + padding * scale * 2.0;
    size.physicalHeight = render->getHeight() + padding * scale * 2.0;
    size.logicalWidth = size.physicalWidth / scale;
    size.logicalHeight = size.physicalHeight / scale;

    auto surface =
        Cairo::SvgSurface::create(svgPath.toStdString(), size.physicalWidth, size.physicalHeight);
    auto context = Cairo::Context::create(surface);
    tex::Graphics2D_cairo g2(context);
    render->draw(g2, padding * scale, padding * scale);
    context->show_page();
  } else {
    QFile svg(svgPath);
    if (svg.open(QIODevice::ReadOnly | QIODevice::Text)) {
      const QString header = QString::fromUtf8(svg.read(512));
      static const QRegularExpression svgSizePattern(
          R"regex(<svg[^>]*\bwidth="([0-9.]+)"[^>]*\bheight="([0-9.]+)")regex");
      const QRegularExpressionMatch match = svgSizePattern.match(header);
      if (match.hasMatch()) {
        size.physicalWidth = match.captured(1).toDouble();
        size.physicalHeight = match.captured(2).toDouble();
        size.logicalWidth = size.physicalWidth / scale;
        size.logicalHeight = size.physicalHeight / scale;
      }
    }
  }

  const QString url = QUrl::fromLocalFile(svgPath).toString().toHtmlEscaped();
  const QString sizeAttrs = size.logicalWidth > 0 && size.logicalHeight > 0
                                ? QStringLiteral(" width=\"%1\" height=\"%2\"")
                                      .arg(qCeil(size.logicalWidth))
                                      .arg(qCeil(size.logicalHeight))
                                : QString();
  const QString style =
      segment.type == Segment::Type::DisplayMath
          ? QStringLiteral("display:block; margin:0.5em auto; max-width:100%;")
          : QStringLiteral("display:inline-block; vertical-align:middle; max-width:100%;");

  return {segment.placeholder,
          QStringLiteral("<img src=\"%1\"%2 style=\"%3\" />").arg(url, sizeAttrs, style)};
}

QString injectRenderedMath(QString html, const std::vector<RenderedMath>& rendered) {
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

QString renderMarkdownToHtml(const QString& markdown, const QString& cacheDir, int maxWidth,
                             qreal textSize, qreal padding, const QColor& foreground,
                             qreal renderScale, QString* error) {
  if (!QDir().mkpath(cacheDir)) {
    if (error)
      *error = QStringLiteral("Failed to create cache directory: %1").arg(cacheDir);
    return {};
  }

  std::call_once(latexInitOnce, []() {
    const QString resRoot = QStringLiteral("/usr/share/clatexmath");
    if (!QDir(resRoot).exists()) {
      latexInitError = QStringLiteral("Missing clatexmath resources at %1").arg(resRoot);
      return;
    }
    tex::LaTeX::init(resRoot.toStdString());
  });

  if (!latexInitError.isEmpty()) {
    if (error)
      *error = latexInitError;
    return {};
  }

  const std::vector<Segment> segments = tokenizeMarkdown(markdown);
  const QString placeholderMarkdown = markdownWithPlaceholders(segments);

  QTextDocument document;
  document.setMarkdown(placeholderMarkdown);
  QString html = document.toHtml();

  std::vector<RenderedMath> rendered;
  rendered.reserve(segments.size());

  std::lock_guard<std::mutex> lock(latexMutex);
  for (const Segment& segment : segments) {
    if (segment.type == Segment::Type::Text)
      continue;
    try {
      rendered.push_back(
          renderSegment(segment, cacheDir, maxWidth, textSize, padding, foreground, renderScale));
    } catch (const std::exception& exception) {
      if (error)
        *error = QString::fromUtf8(exception.what());
      return {};
    } catch (...) {
      if (error)
        *error = QStringLiteral("Unknown LaTeX render error");
      return {};
    }
  }

  return injectRenderedMath(html, rendered);
}

} // namespace

MathRenderer::MathRenderer(QObject* parent) : QObject(parent) {}

void MathRenderer::renderMarkdown(const QString& requestId, const QString& markdown,
                                  const QString& cacheDir, int maxWidth, qreal textSize,
                                  qreal padding, const QString& foreground, qreal renderScale) {
  QPointer<MathRenderer> self(this);
  (void)QtConcurrent::run([self, requestId, markdown, cacheDir, maxWidth, textSize, padding,
                           foreground, renderScale]() {
    const QColor color(foreground);
    const QColor resolvedColor = color.isValid() ? color : QColor(QStringLiteral("#000000"));
    const qreal resolvedScale = std::clamp<qreal>(renderScale, 1.0, 4.0);
    QString error;
    const QString html = renderMarkdownToHtml(
        markdown, cacheDir, std::max(120, maxWidth), textSize > 0 ? textSize : 18.0,
        padding >= 0 ? padding : 4.0, resolvedColor, resolvedScale, &error);

    if (!self)
      return;

    if (!error.isEmpty()) {
      QMetaObject::invokeMethod(
          self,
          [self, requestId, error]() {
            if (self)
              self->requestFailed(requestId, error);
          },
          Qt::QueuedConnection);
      return;
    }

    QMetaObject::invokeMethod(
        self,
        [self, requestId, html]() {
          if (self)
            self->requestFinished(requestId, html);
        },
        Qt::QueuedConnection);
  });
}
