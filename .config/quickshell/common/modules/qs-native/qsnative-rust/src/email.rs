#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GmailAccount {
    pub id: String,
    pub address: String,
}

impl GmailAccount {
    pub fn load(id: &str, address: &str) -> Result<Self, String> {
        let id = id.trim();
        if id.is_empty() {
            return Err("Gmail account id is required".to_owned());
        }
        let address = address.trim();
        if address.is_empty() {
            return Err(format!("Gmail account {id} address is required"));
        }

        Ok(Self {
            id: id.to_owned(),
            address: address.to_owned(),
        })
    }
}
