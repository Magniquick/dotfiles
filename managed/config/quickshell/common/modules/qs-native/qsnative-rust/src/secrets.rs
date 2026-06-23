use std::collections::HashMap;
use std::error::Error;

use secret_service::{blocking::SecretService, EncryptionType};
use secret_service::SecretService as AsyncSecretService;

pub const DEFAULT_SERVICE: &str = "quickshell";

type SecretResult<T> = Result<T, Box<dyn Error>>;

pub fn normalize_key(key: &str) -> Option<String> {
    let key = key.trim();
    (!key.is_empty()).then(|| key.to_owned())
}

pub fn lookup(key: &str) -> Option<String> {
    let key = normalize_key(key)?;
    let service = SecretService::connect(EncryptionType::Dh).ok()?;
    let items = service.search_items(secret_attrs(&key)).ok()?;

    if !items.locked.is_empty() {
        let locked = items.locked.iter().collect::<Vec<_>>();
        service.unlock_all(&locked).ok()?;
    }

    if let Some(item) = items.unlocked.iter().chain(items.locked.iter()).next() {
        let secret = String::from_utf8(item.get_secret().ok()?).ok()?;
        return Some(secret);
    }

    None
}

pub fn set(key: &str, value: &str) -> SecretResult<()> {
    let key = require_key(key)?;
    let service = SecretService::connect(EncryptionType::Dh)?;
    let collection = service.get_default_collection()?;

    if collection.is_locked()? {
        collection.unlock()?;
    }

    collection.create_item(
        &key,
        secret_attrs(&key),
        value.as_bytes(),
        true,
        "text/plain",
    )?;
    Ok(())
}

pub fn delete(key: &str) -> SecretResult<()> {
    let key = require_key(key)?;
    let service = SecretService::connect(EncryptionType::Dh)?;
    let items = service.search_items(secret_attrs(&key))?;

    if !items.locked.is_empty() {
        let locked = items.locked.iter().collect::<Vec<_>>();
        service.unlock_all(&locked)?;
    }

    for item in items.unlocked.iter().chain(items.locked.iter()) {
        item.delete()?;
    }

    Ok(())
}

pub async fn lookup_async(key: &str) -> Option<String> {
    let key = normalize_key(key)?;
    let service = AsyncSecretService::connect(EncryptionType::Dh).await.ok()?;
    let items = service.search_items(secret_attrs(&key)).await.ok()?;
    if !items.locked.is_empty() {
        service.unlock_all(items.locked.iter().collect::<Vec<_>>().as_slice()).await.ok()?;
    }
    let item = items.unlocked.iter().chain(items.locked.iter()).next()?;
    String::from_utf8(item.get_secret().await.ok()?).ok()
}

pub async fn set_async(key: &str, value: &str) -> SecretResult<()> {
    let key = require_key(key)?;
    let service = AsyncSecretService::connect(EncryptionType::Dh).await?;
    let collection = service.get_default_collection().await?;
    if collection.is_locked().await? {
        collection.unlock().await?;
    }
    collection.create_item(&key, secret_attrs(&key), value.as_bytes(), true, "text/plain").await?;
    Ok(())
}

fn require_key(key: &str) -> SecretResult<String> {
    normalize_key(key).ok_or_else(|| "secret key is required".into())
}

fn secret_attrs(key: &str) -> HashMap<&str, &str> {
    HashMap::from([("service", DEFAULT_SERVICE), ("key", key)])
}

#[cfg(test)]
mod tests {
    use super::normalize_key;

    #[test]
    fn normalizes_secret_keys() {
        assert_eq!(normalize_key("  TOKEN \n"), Some("TOKEN".to_owned()));
        assert_eq!(normalize_key(" \t\n"), None);
    }
}
