//! SSH connection storage and management
//!
//! Stores connection metadata in a JSON file in the app's config directory.
//! Credentials (passwords) are stored separately in the OS keychain.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use uuid::Uuid;

/// SSH authentication method
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum AuthMethod {
    /// SSH key authentication (default, most secure)
    Key {
        /// Path to private key file (optional, uses default ~/.ssh/id_rsa if not specified)
        key_path: Option<String>,
    },
    /// Password authentication (stored in keychain)
    Password,
    /// SSH agent (uses system SSH agent)
    Agent,
}

impl Default for AuthMethod {
    fn default() -> Self {
        AuthMethod::Key { key_path: None }
    }
}

/// Stored SSH connection (without sensitive data)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SSHConnection {
    /// Unique identifier
    pub id: String,
    /// Display name for the connection
    pub name: String,
    /// SSH host (IP or hostname)
    pub host: String,
    /// SSH port (default: 22)
    pub port: u16,
    /// Username for authentication
    pub username: String,
    /// Authentication method
    pub auth_method: AuthMethod,
    /// Default path to scan on connection
    pub default_path: Option<String>,
    /// Connection timeout in seconds
    pub timeout_secs: u32,
    /// Creation timestamp
    pub created_at: i64,
    /// Last used timestamp
    pub last_used_at: Option<i64>,
}

/// Input for creating/updating a connection
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SSHConnectionInput {
    /// Optional ID (for updates)
    pub id: Option<String>,
    /// Display name
    pub name: String,
    /// SSH host
    pub host: String,
    /// SSH port
    pub port: Option<u16>,
    /// Username
    pub username: String,
    /// Authentication method
    pub auth_method: AuthMethod,
    /// Password (only if auth_method is Password)
    pub password: Option<String>,
    /// Default path to scan
    pub default_path: Option<String>,
    /// Timeout in seconds
    pub timeout_secs: Option<u32>,
}

/// Get the connections file path
fn get_connections_file() -> Result<PathBuf, String> {
    let config_dir = dirs::config_dir()
        .ok_or_else(|| "Could not find config directory".to_string())?
        .join("data-x");

    fs::create_dir_all(&config_dir)
        .map_err(|e| format!("Failed to create config directory: {}", e))?;

    Ok(config_dir.join("ssh_connections.json"))
}

/// Load all connections from storage
fn load_connections() -> Result<Vec<SSHConnection>, String> {
    let path = get_connections_file()?;

    if !path.exists() {
        return Ok(Vec::new());
    }

    let content = fs::read_to_string(&path)
        .map_err(|e| format!("Failed to read connections file: {}", e))?;

    serde_json::from_str(&content)
        .map_err(|e| format!("Failed to parse connections file: {}", e))
}

/// Save all connections to storage
fn save_connections(connections: &[SSHConnection]) -> Result<(), String> {
    let path = get_connections_file()?;

    let content = serde_json::to_string_pretty(connections)
        .map_err(|e| format!("Failed to serialize connections: {}", e))?;

    fs::write(&path, content)
        .map_err(|e| format!("Failed to write connections file: {}", e))
}

/// Get all stored SSH connections
pub fn get_all_connections() -> Result<Vec<SSHConnection>, String> {
    load_connections()
}

/// Get a specific connection by ID
pub fn get_connection(id: &str) -> Result<Option<SSHConnection>, String> {
    let connections = load_connections()?;
    Ok(connections.into_iter().find(|c| c.id == id))
}

/// Save a new SSH connection
pub fn save_connection(input: SSHConnectionInput) -> Result<SSHConnection, String> {
    let mut connections = load_connections()?;

    let now = chrono::Utc::now().timestamp();
    let id = input.id.unwrap_or_else(|| Uuid::new_v4().to_string());

    // Check for duplicate ID (shouldn't happen with UUID, but be safe)
    if connections.iter().any(|c| c.id == id) {
        return Err("Connection with this ID already exists".to_string());
    }

    let connection = SSHConnection {
        id: id.clone(),
        name: input.name,
        host: input.host,
        port: input.port.unwrap_or(22),
        username: input.username,
        auth_method: input.auth_method.clone(),
        default_path: input.default_path,
        timeout_secs: input.timeout_secs.unwrap_or(30),
        created_at: now,
        last_used_at: None,
    };

    // Store password in keychain if provided
    if let Some(password) = input.password {
        if matches!(input.auth_method, AuthMethod::Password) {
            super::credentials::store_credential(&id, &password)?;
        }
    }

    connections.push(connection.clone());
    save_connections(&connections)?;

    Ok(connection)
}

/// Update an existing SSH connection
pub fn update_connection(input: SSHConnectionInput) -> Result<SSHConnection, String> {
    let id = input
        .id
        .as_ref()
        .ok_or_else(|| "Connection ID is required for update".to_string())?;

    let mut connections = load_connections()?;
    let now = chrono::Utc::now().timestamp();

    let index = connections
        .iter()
        .position(|c| &c.id == id)
        .ok_or_else(|| "Connection not found".to_string())?;

    let old_connection = &connections[index];

    let connection = SSHConnection {
        id: id.clone(),
        name: input.name,
        host: input.host,
        port: input.port.unwrap_or(22),
        username: input.username,
        auth_method: input.auth_method.clone(),
        default_path: input.default_path,
        timeout_secs: input.timeout_secs.unwrap_or(30),
        created_at: old_connection.created_at,
        last_used_at: Some(now),
    };

    // Update password in keychain if provided
    if let Some(password) = input.password {
        if matches!(input.auth_method, AuthMethod::Password) {
            super::credentials::store_credential(id, &password)?;
        }
    }

    connections[index] = connection.clone();
    save_connections(&connections)?;

    Ok(connection)
}

/// Delete an SSH connection
pub fn delete_connection(id: &str) -> Result<(), String> {
    let mut connections = load_connections()?;

    let initial_len = connections.len();
    connections.retain(|c| c.id != id);

    if connections.len() == initial_len {
        return Err("Connection not found".to_string());
    }

    // Also delete credential from keychain
    let _ = super::credentials::delete_credential(id);

    save_connections(&connections)
}

/// Update the last_used_at timestamp for a connection
pub fn mark_connection_used(id: &str) -> Result<(), String> {
    let mut connections = load_connections()?;
    let now = chrono::Utc::now().timestamp();

    if let Some(connection) = connections.iter_mut().find(|c| c.id == id) {
        connection.last_used_at = Some(now);
        save_connections(&connections)?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_auth_method_serialization() {
        let key_auth = AuthMethod::Key {
            key_path: Some("/path/to/key".to_string()),
        };
        let json = serde_json::to_string(&key_auth).unwrap();
        assert!(json.contains("key"));

        let password_auth = AuthMethod::Password;
        let json = serde_json::to_string(&password_auth).unwrap();
        assert!(json.contains("password"));
    }
}
