#include "QsNativeConfigResolver.h"
#include "QsNativeGlue.h"
#include "qsnative_api.h"

QsNativeConfigResolver::QsNativeConfigResolver(QObject* parent)
    : QObject(parent), m_handle(QsNative_ConfigResolver_New()) {}

QsNativeConfigResolver::~QsNativeConfigResolver() {
  QsNative_ConfigResolver_Delete(m_handle);
}

// Synchronous: Rust resolves config + secrets and returns an owned JSON object
// (string -> string) that we own and must free.
// TODO(stage2): backend is a stub, so this currently yields an empty map.
auto QsNativeConfigResolver::refresh() -> bool {
  QVariantMap next = qsn::takeObject(QsNative_ConfigResolver_Refresh(m_handle));

  if (next != m_values) {
    m_values = next;
    emit valuesChanged();
  }
  return true;
}
