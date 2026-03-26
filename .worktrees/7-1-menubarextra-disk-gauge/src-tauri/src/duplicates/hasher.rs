use sha2::{Sha256, Digest};
use std::fs::File;
use std::io::{BufReader, Read};
use std::path::Path;

const PARTIAL_HASH_SIZE: usize = 4 * 1024; // 4KB for partial hash

/// Calculate SHA-256 hash of the first N bytes of a file (partial hash)
pub fn partial_hash(path: &Path) -> Result<String, std::io::Error> {
    let file = File::open(path)?;
    let mut reader = BufReader::new(file);
    let mut buffer = vec![0u8; PARTIAL_HASH_SIZE];

    let bytes_read = reader.read(&mut buffer)?;
    buffer.truncate(bytes_read);

    let mut hasher = Sha256::new();
    hasher.update(&buffer);
    let result = hasher.finalize();

    Ok(format!("{:x}", result))
}

/// Calculate SHA-256 hash of the entire file
pub fn full_hash(path: &Path) -> Result<String, std::io::Error> {
    let file = File::open(path)?;
    let mut reader = BufReader::with_capacity(64 * 1024, file); // 64KB buffer
    let mut hasher = Sha256::new();

    let mut buffer = [0u8; 64 * 1024];
    loop {
        let bytes_read = reader.read(&mut buffer)?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }

    let result = hasher.finalize();
    Ok(format!("{:x}", result))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    #[test]
    fn test_partial_hash_small_file() {
        let mut file = NamedTempFile::new().unwrap();
        file.write_all(b"Hello, World!").unwrap();

        let hash = partial_hash(file.path()).unwrap();
        assert!(!hash.is_empty());
        assert_eq!(hash.len(), 64); // SHA-256 produces 64 hex chars
    }

    #[test]
    fn test_full_hash() {
        let mut file = NamedTempFile::new().unwrap();
        file.write_all(b"Hello, World!").unwrap();

        let hash = full_hash(file.path()).unwrap();
        assert!(!hash.is_empty());
        assert_eq!(hash.len(), 64);
    }

    #[test]
    fn test_identical_files_same_hash() {
        let content = b"Test content for duplicate detection";

        let mut file1 = NamedTempFile::new().unwrap();
        file1.write_all(content).unwrap();

        let mut file2 = NamedTempFile::new().unwrap();
        file2.write_all(content).unwrap();

        let hash1 = full_hash(file1.path()).unwrap();
        let hash2 = full_hash(file2.path()).unwrap();

        assert_eq!(hash1, hash2);
    }
}
