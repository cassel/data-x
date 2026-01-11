//! SSH connection management for Data-X GUI
//!
//! Provides secure SSH connection storage, credential management,
//! and remote scanning integration.

pub mod connection_manager;
pub mod credentials;
pub mod remote_scan;

#[allow(unused_imports)]
pub use connection_manager::{
    delete_connection, get_all_connections, get_connection, save_connection, update_connection,
    AuthMethod, SSHConnection, SSHConnectionInput,
};
// Credentials are used internally by connection_manager and remote_scan
#[allow(unused_imports)]
pub use credentials::{delete_credential, get_credential, store_credential};
pub use remote_scan::{scan_remote_directory, test_connection, SSHTestResult};
