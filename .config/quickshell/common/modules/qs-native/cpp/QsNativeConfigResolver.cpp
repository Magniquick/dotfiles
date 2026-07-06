#include "QsNativeConfigResolver.h"
#include "QsNativeGlue.h"
#include "qsnative_api.h"

#include <QString>

auto QsNativeConfigResolver::refresh() -> bool {
  QsNative_ConfigResolver_Refresh(this, &QsNativeConfigResolver::entriesCallback);
  return true;
}

void QsNativeConfigResolver::entriesCallback(void* ctx, const ConfigEntryC* entries, size_t len) {
  auto* self = static_cast<QsNativeConfigResolver*>(ctx);

  // Deep-copy synchronously: the char* fields are only valid for this call.
  QVariantMap values;
  for (size_t i = 0; i < len; ++i) {
    values.insert(QString::fromUtf8(entries[i].key), QString::fromUtf8(entries[i].value));
  }

  qsn::postToObject(self, [self, values]() { self->applyValues(values); });
}

void QsNativeConfigResolver::applyValues(const QVariantMap& values) {
  m_values = values;
  emit valuesChanged();
}
