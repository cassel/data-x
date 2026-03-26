//! Secure credential storage using OS keychain
//!
//! Uses the `keyring` crate to store SSH passwords securely:
//! - macOS: Keychain
//! - Windows: Credential Manager
//! - Linux: Secret Service (GNOME Keyring, KWallet, etc.)

use keyring::Entry;

const SERVICE_NAME: &str = "data-x-ssh";

/// Store a credential (password) in the OS keychain
pub fn store_credential(connection_id: &str, password: &str) -> Result<(), String> {
    let entry = Entry::new(SERVICE_NAME, connection_id)
        .map_err(|e| format!("Failed to create keychain entry: {}", e))?;

    entry
        .set_password(password)
        .map_err(|e| format!("Failed to store password in keychain: {}", e))
}

/// Retrieve a credential (password) from the OS keychain
pub fn get_credential(connection_id: &str) -> Result<Option<String>, String> {
    let entry = Entry::new(SERVICE_NAME, connection_id)
        .map_err(|e| format!("Failed to access keychain: {}", e))?;

    match entry.get_password() {
        Ok(password) => Ok(Some(password)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(format!("Failed to retrieve password from keychain: {}", e)),
    }
}

/// Delete a credential from the OS keychain
pub fn delete_credential(connection_id: &str) -> Result<(), String> {
    let entry = Entry::new(SERVICE_NAME, connection_id)
        .map_err(|e| format!("Failed to access keychain: {}", e))?;

    match entry.delete_credential() {
        Ok(()) => Ok(()),
        Err(keyring::Error::NoEntry) => Ok(()), // Already deleted, that's fine
        Err(e) => Err(format!("Failed to delete password from keychain: {}", e)),
    }
}

/// Check if a credential exists in the keychain (without retrieving it)
#[allow(dead_code)]
pub fn has_credential(connection_id: &str) -> Result<bool, String> {
    let entry = Entry::new(SERVICE_NAME, connection_id)
        .map_err(|e| format!("Failed to access keychain: {}", e))?;

    match entry.get_password() {
        Ok(_) => Ok(true),
        Err(keyring::Error::NoEntry) => Ok(false),
        Err(e) => Err(format!("Failed to check keychain: {}", e)),
    }
}

#[cfg(test)]
mod tests {
    // Note: These tests require a functioning keychain/secret service
    // They are disabled by default as they may require user interaction
    // on some systems.

    #[test]
    #[ignore]
    fn test_store_and_retrieve() {
        use super::*;

        let test_id = "test-connection-12345";
        let test_password = "super-secret-password";

        // Store
        store_credential(test_id, test_password).expect("Failed to store");

        // Retrieve
        let retrieved = get_credential(test_id).expect("Failed to get");
        assert_eq!(retrieved, Some(test_password.to_string()));

        // Delete
        delete_credential(test_id).expect("Failed to delete");

        // Verify deleted
        let after_delete = get_credential(test_id).expect("Failed to get after delete");
        assert_eq!(after_delete, None);
    }
}
