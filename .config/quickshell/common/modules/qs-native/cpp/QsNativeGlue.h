#pragma once

// Shared glue for the hand-written QObject bindings over the Rust `extern "C"`
// ABI. Header-only (all inline) so it adds no translation unit or link step.
//
// Two duplicated patterns live here:
//   1. take*(): consume a Rust-owned `char*` (JSON or plain text), converting to
//      a Qt value and freeing it with QsNative_Free.
//   2. postToObject(): marshal a callable from a worker thread onto a QObject's
//      thread (the queued-invoke used by every threaded provider callback).

#include "qsnative_api.h"

#include <QByteArray>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

#include <utility>

namespace qsn {

// ---- Rust-owned `char*` -> Qt (frees the pointer with QsNative_Free) --------

/// Parses a Rust-owned JSON `char*` into a document and frees it. Null-safe.
[[nodiscard]] inline auto takeDoc(char* raw) -> QJsonDocument {
  if (raw == nullptr) {
    return {};
  }
  const QByteArray json(raw);
  QsNative_Free(raw);
  return QJsonDocument::fromJson(json);
}

/// Parses a Rust-owned JSON object `char*` into a `QVariantMap` (empty on error).
[[nodiscard]] inline auto takeObject(char* raw) -> QVariantMap {
  const QJsonDocument doc = takeDoc(raw);
  return doc.isObject() ? doc.object().toVariantMap() : QVariantMap{};
}

/// Parses a Rust-owned JSON array `char*` into a `QVariantList` (empty on error).
[[nodiscard]] inline auto takeList(char* raw) -> QVariantList {
  const QJsonDocument doc = takeDoc(raw);
  return doc.isArray() ? doc.array().toVariantList() : QVariantList{};
}

/// Takes a Rust-owned plain-text `char*` as a `QString` and frees it. Null-safe.
[[nodiscard]] inline auto takeString(char* raw) -> QString {
  if (raw == nullptr) {
    return {};
  }
  const QString out = QString::fromUtf8(raw);
  QsNative_Free(raw);
  return out;
}

// ---- Worker thread -> QObject thread ----------------------------------------

/// Marshals `fn` onto `obj`'s thread. Call from a Rust worker-thread C callback
/// after copying any borrowed data out of the transient ABI buffers.
template <class F>
inline void postToObject(QObject* obj, F&& fn) {
  QMetaObject::invokeMethod(obj, std::forward<F>(fn), Qt::QueuedConnection);
}

} // namespace qsn
