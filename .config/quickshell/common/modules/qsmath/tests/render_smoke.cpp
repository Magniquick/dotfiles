#include "MathRenderer.h"

#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QXmlStreamReader>
#include <QtTest/QtTest>

class MathRendererSmokeTest : public QObject {
  Q_OBJECT

private slots:
  static void rendersInlineMathToCachedSvg();
  static void rendersInlineMathWithoutPaddedSvgBounds();
  static void rendersInlineMathAsTightInlineImage();
  static void rendersBracketDisplayMath();
  static void rendersMultilineBracketDisplayMath();
  static void reportsRatexParseFailures();
  static void readsSingleQuotedSvgSizeInAnyAttributeOrder();
  static void readsSvgSizeFromViewBoxFallback();
  // TODO(stage2): reinstate MarkdownStreamModel tests once the real streaming
  // model replaces the stub.
};

static auto waitForRender(QSignalSpy& finished, QSignalSpy& failed, QList<QVariant>* result,
                          QString* error) -> bool {
  while (finished.isEmpty() && failed.isEmpty()) {
    if (!finished.wait(5000) && failed.isEmpty()) {
      if (error != nullptr) {
        *error = QStringLiteral("Timed out waiting for MathRenderer");
      }
      return false;
    }
  }

  if (!failed.isEmpty()) {
    if (error != nullptr) {
      *error = failed.takeFirst().at(1).toString();
    }
    return false;
  }

  if (finished.size() != 1) {
    if (error != nullptr) {
      *error = QStringLiteral("Expected one finished signal, got %1").arg(finished.size());
    }
    return false;
  }

  if (result != nullptr) {
    *result = finished.takeFirst();
  }
  return true;
}

static auto cacheContainsSvg(const QString& cachePath, const QString& expectedColor, QString* error)
    -> bool {
  const QStringList svgs =
      QDir(cachePath).entryList(QStringList{QStringLiteral("*.svg")}, QDir::Files);
  if (svgs.isEmpty()) {
    if (error != nullptr) {
      *error = QStringLiteral("No SVG files were written to %1").arg(cachePath);
    }
    return false;
  }

  QFile svg(QDir(cachePath).filePath(svgs.first()));
  if (!svg.open(QIODevice::ReadOnly | QIODevice::Text)) {
    if (error != nullptr) {
      *error = QStringLiteral("Failed to read %1").arg(svg.fileName());
    }
    return false;
  }

  const QString svgText = QString::fromUtf8(svg.readAll());
  if (!svgText.contains(QStringLiteral("<svg"))) {
    if (error != nullptr) {
      *error = QStringLiteral("Cached file is not an SVG: %1").arg(svg.fileName());
    }
    return false;
  }

  if (svgText.contains(QStringLiteral("rgba("))) {
    if (error != nullptr) {
      *error =
          QStringLiteral("Cached SVG still contains rgba() paint values: %1").arg(svg.fileName());
    }
    return false;
  }

  if (!svgText.contains(expectedColor, Qt::CaseInsensitive)) {
    if (error != nullptr) {
      *error = QStringLiteral("Cached SVG does not contain expected color %1: %2")
                   .arg(expectedColor, svg.fileName());
    }
    return false;
  }

  return true;
}

static auto parseSvgLength(const QString& text, qreal* value) -> bool {
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

static auto parseSvgViewBox(const QString& viewBox, qreal* width, qreal* height) -> bool {
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

static auto readSingleSvgSize(const QString& cachePath, qreal* width, qreal* height, QString* error)
    -> bool {
  const QStringList svgs =
      QDir(cachePath).entryList(QStringList{QStringLiteral("*.svg")}, QDir::Files);
  if (svgs.size() != 1) {
    if (error != nullptr) {
      *error = QStringLiteral("Expected one SVG in %1, got %2").arg(cachePath).arg(svgs.size());
    }
    return false;
  }

  QFile svg(QDir(cachePath).filePath(svgs.first()));
  if (!svg.open(QIODevice::ReadOnly | QIODevice::Text)) {
    if (error != nullptr) {
      *error = QStringLiteral("Failed to read %1").arg(svg.fileName());
    }
    return false;
  }

  QXmlStreamReader xml(&svg);
  while (!xml.atEnd()) {
    xml.readNext();
    if (!xml.isStartElement()) {
      continue;
    }
    if (xml.name() != QLatin1String("svg")) {
      break;
    }

    const QXmlStreamAttributes attributes = xml.attributes();
    qreal parsedWidth = 0;
    qreal parsedHeight = 0;
    const bool hasWidth =
        parseSvgLength(attributes.value(QStringLiteral("width")).toString(), &parsedWidth);
    const bool hasHeight =
        parseSvgLength(attributes.value(QStringLiteral("height")).toString(), &parsedHeight);

    if ((!hasWidth || !hasHeight) &&
        !parseSvgViewBox(attributes.value(QStringLiteral("viewBox")).toString(), &parsedWidth,
                         &parsedHeight)) {
      break;
    }

    if (width != nullptr) {
      *width = parsedWidth;
    }
    if (height != nullptr) {
      *height = parsedHeight;
    }
    return true;
  }

  if (error != nullptr) {
    *error = QStringLiteral("Cached SVG does not expose width and height: %1").arg(svg.fileName());
  }
  return false;
}

static auto writeSvgFixture(const QString& cachePath, const QString& svgText, QString* error)
    -> bool {
  QFile svg(QDir(cachePath).filePath(QStringLiteral("fixture.svg")));
  if (!svg.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate)) {
    if (error != nullptr) {
      *error = QStringLiteral("Failed to write fixture SVG: %1").arg(svg.fileName());
    }
    return false;
  }
  svg.write(svgText.toUtf8());
  return true;
}

void MathRendererSmokeTest::rendersInlineMathToCachedSvg() {
  QTemporaryDir const cacheDir;
  QVERIFY(cacheDir.isValid());

  MathRenderer renderer;
  QSignalSpy finished(&renderer, &MathRenderer::requestFinished);
  QSignalSpy failed(&renderer, &MathRenderer::requestFailed);

  renderer.renderMarkdown(QStringLiteral("smoke"), QStringLiteral("Euler $x^2$ works"),
                          cacheDir.path(), 640, 18.0, 4.0, QStringLiteral("#ffffff"), 1.0);

  QList<QVariant> result;
  QString error;
  QVERIFY2(waitForRender(finished, failed, &result, &error), qPrintable(error));
  QCOMPARE(result.at(0).toString(), QStringLiteral("smoke"));

  const QString html = result.at(1).toString();
  QVERIFY2(html.contains(QStringLiteral("<img")), qPrintable(html));
  QVERIFY2(html.contains(QStringLiteral("#ffffff"), Qt::CaseInsensitive), qPrintable(html));
  QVERIFY2(cacheContainsSvg(cacheDir.path(), QStringLiteral("#ffffff"), &error), qPrintable(error));
}

void MathRendererSmokeTest::rendersInlineMathWithoutPaddedSvgBounds() {
  QTemporaryDir const cacheDir;
  QVERIFY(cacheDir.isValid());

  MathRenderer renderer;
  QSignalSpy finished(&renderer, &MathRenderer::requestFinished);
  QSignalSpy failed(&renderer, &MathRenderer::requestFailed);

  renderer.renderMarkdown(QStringLiteral("trim-inline"), QStringLiteral("$O(n^2)$"),
                          cacheDir.path(), 360, 13.0, 2.0, QStringLiteral("#ffffff"), 1.0);

  QList<QVariant> result;
  QString error;
  QVERIFY2(waitForRender(finished, failed, &result, &error), qPrintable(error));

  qreal width = 0;
  qreal height = 0;
  QVERIFY2(readSingleSvgSize(cacheDir.path(), &width, &height, &error), qPrintable(error));
  QVERIFY2(width < 46.0, qPrintable(QStringLiteral("width was %1").arg(width)));
  QVERIFY2(height < 24.0, qPrintable(QStringLiteral("height was %1").arg(height)));
}

void MathRendererSmokeTest::rendersInlineMathAsTightInlineImage() {
  QTemporaryDir const cacheDir;
  QVERIFY(cacheDir.isValid());

  MathRenderer renderer;
  QSignalSpy finished(&renderer, &MathRenderer::requestFinished);
  QSignalSpy failed(&renderer, &MathRenderer::requestFailed);

  renderer.renderMarkdown(
      QStringLiteral("inline-tight"),
      QStringLiteral("Elegant: it turns an expensive $O(n^2)$ DFT into $O(n\\log n)$."),
      cacheDir.path(), 360, 18.0, 4.0, QStringLiteral("#ffffff"), 1.0);

  QList<QVariant> result;
  QString error;
  QVERIFY2(waitForRender(finished, failed, &result, &error), qPrintable(error));

  const QString html = result.at(1).toString();
  QCOMPARE(html.count(QStringLiteral("<img")), 2);
  QVERIFY2(html.contains(QRegularExpression(R"(<img\b[^>]*\bwidth="\d+"[^>]*\bheight="\d+")")),
           qPrintable(html));
  QVERIFY2(!html.contains(QStringLiteral("display:inline-block")), qPrintable(html));
  QVERIFY2(!html.contains(QStringLiteral("max-width:100%")), qPrintable(html));
}

void MathRendererSmokeTest::rendersBracketDisplayMath() {
  QTemporaryDir const cacheDir;
  QVERIFY(cacheDir.isValid());

  MathRenderer renderer;
  QSignalSpy finished(&renderer, &MathRenderer::requestFinished);
  QSignalSpy failed(&renderer, &MathRenderer::requestFailed);

  renderer.renderMarkdown(QStringLiteral("display"), QStringLiteral("\\[x^2 + y^2\\]"),
                          cacheDir.path(), 640, 18.0, 4.0, QStringLiteral("#ffffff"), 1.0);

  QList<QVariant> result;
  QString error;
  QVERIFY2(waitForRender(finished, failed, &result, &error), qPrintable(error));
  QCOMPARE(result.at(0).toString(), QStringLiteral("display"));
  QVERIFY2(result.at(1).toString().contains(QStringLiteral("<img")),
           qPrintable(result.at(1).toString()));
  QVERIFY2(cacheContainsSvg(cacheDir.path(), QStringLiteral("#ffffff"), &error), qPrintable(error));
}

void MathRendererSmokeTest::rendersMultilineBracketDisplayMath() {
  QTemporaryDir const cacheDir;
  QVERIFY(cacheDir.isValid());

  MathRenderer renderer;
  QSignalSpy finished(&renderer, &MathRenderer::requestFinished);
  QSignalSpy failed(&renderer, &MathRenderer::requestFailed);

  renderer.renderMarkdown(QStringLiteral("aligned"),
                          QStringLiteral("\\[\n\\begin{aligned}\nf(x) &= x^3 - 2x + 1 \\\\\n"
                                         "f'(x) &= 3x^2 - 2\n\\end{aligned}\n\\]"),
                          cacheDir.path(), 640, 18.0, 4.0, QStringLiteral("#ffffff"), 1.0);

  QList<QVariant> result;
  QString error;
  QVERIFY2(waitForRender(finished, failed, &result, &error), qPrintable(error));
  QCOMPARE(result.at(0).toString(), QStringLiteral("aligned"));
  QVERIFY2(result.at(1).toString().contains(QStringLiteral("<img")),
           qPrintable(result.at(1).toString()));
  QVERIFY2(cacheContainsSvg(cacheDir.path(), QStringLiteral("#ffffff"), &error), qPrintable(error));
}

void MathRendererSmokeTest::reportsRatexParseFailures() {
  QTemporaryDir const cacheDir;
  QVERIFY(cacheDir.isValid());

  MathRenderer renderer;
  QSignalSpy const finished(&renderer, &MathRenderer::requestFinished);
  QSignalSpy failed(&renderer, &MathRenderer::requestFailed);

  renderer.renderMarkdown(QStringLiteral("bad"), QStringLiteral("$\\notacommand{$"),
                          cacheDir.path(), 640, 18.0, 4.0, QStringLiteral("#ffffff"), 1.0);

  while (finished.isEmpty() && failed.isEmpty()) {
    QVERIFY(failed.wait(5000) || !finished.isEmpty());
  }

  QVERIFY(finished.isEmpty());
  QCOMPARE(failed.size(), 1);
  QCOMPARE(failed.takeFirst().at(0).toString(), QStringLiteral("bad"));
}

void MathRendererSmokeTest::readsSingleQuotedSvgSizeInAnyAttributeOrder() {
  QTemporaryDir const cacheDir;
  QVERIFY(cacheDir.isValid());

  QString error;
  QVERIFY2(writeSvgFixture(cacheDir.path(),
                           QStringLiteral("<svg height='24.5' viewBox='0 0 1 1' width='48.25' "
                                          "xmlns='http://www.w3.org/2000/svg'/>"),
                           &error),
           qPrintable(error));

  qreal width = 0;
  qreal height = 0;
  QVERIFY2(readSingleSvgSize(cacheDir.path(), &width, &height, &error), qPrintable(error));
  QCOMPARE(width, 48.25);
  QCOMPARE(height, 24.5);
}

void MathRendererSmokeTest::readsSvgSizeFromViewBoxFallback() {
  QTemporaryDir const cacheDir;
  QVERIFY(cacheDir.isValid());

  QString error;
  QVERIFY2(writeSvgFixture(cacheDir.path(),
                           QStringLiteral("<svg viewBox='-2, -3, 120.5, 64.25' "
                                          "xmlns='http://www.w3.org/2000/svg'/>"),
                           &error),
           qPrintable(error));

  qreal width = 0;
  qreal height = 0;
  QVERIFY2(readSingleSvgSize(cacheDir.path(), &width, &height, &error), qPrintable(error));
  QCOMPARE(width, 120.5);
  QCOMPARE(height, 64.25);
}

QTEST_MAIN(MathRendererSmokeTest)
#include "render_smoke.moc"
