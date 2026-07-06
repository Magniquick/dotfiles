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
#include <QCborValue>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QString>
#include <QVariant>
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

// ---- Rust-owned CBOR bytes -> Qt (frees the buffer with QsNative_FreeBytes) --
//
// CBOR replaces the JSON char* hop where Rust would otherwise serialize a struct
// only for the FFI. Qt parses it natively (QCborValue), so there is no new C++
// dependency. QCborValue::fromCbor copies the range; the buffer is freed here.

/// Parses a Rust-owned CBOR buffer into a QVariant and frees it. Null-safe.
[[nodiscard]] inline auto takeCbor(QsNativeBytes bytes) -> QVariant {
  if (bytes.ptr == nullptr) {
    return {};
  }
  const QByteArray buf(reinterpret_cast<const char*>(bytes.ptr),
                       static_cast<qsizetype>(bytes.len));
  const QVariant out = QCborValue::fromCbor(buf).toVariant();
  QsNative_FreeBytes(bytes);
  return out;
}

/// Parses a Rust-owned CBOR object into a QVariantMap (empty on non-object).
[[nodiscard]] inline auto takeCborObject(QsNativeBytes bytes) -> QVariantMap {
  return takeCbor(bytes).toMap();
}

/// Parses a Rust-owned CBOR array into a QVariantList (empty on non-array).
[[nodiscard]] inline auto takeCborList(QsNativeBytes bytes) -> QVariantList {
  return takeCbor(bytes).toList();
}

// ---- Qt -> CBOR bytes for passing into Rust ---------------------------------

/// Encodes a Qt value to CBOR bytes. The returned QByteArray owns the buffer;
/// pass `.constData()` + `.size()` to the Rust fn and keep it alive across the
/// call.
[[nodiscard]] inline auto toCbor(const QVariant& value) -> QByteArray {
  return QCborValue::fromVariant(value).toCbor();
}

// ---- Worker thread -> QObject thread ----------------------------------------

/// Marshals `fn` onto `obj`'s thread. Call from a Rust worker-thread C callback
/// after copying any borrowed data out of the transient ABI buffers.
template <class F>
inline void postToObject(QObject* obj, F&& fn) {
  QMetaObject::invokeMethod(obj, std::forward<F>(fn), Qt::QueuedConnection);
}

} // namespace qsn
