#![allow(nonstandard_style)]
use godot::prelude::*;
use godot::classes::ProjectSettings;
use rusqlite::{Connection, params, Result as SqlResult};
use serde::{Deserialize, Serialize};
use walkdir::WalkDir;
use regex::Regex;

#[derive(Serialize, Deserialize, Debug, Clone)]
struct AssetData {
    path: String,
    name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    image_path: Option<String>,
    #[serde(default)]
    tags: Vec<String>,
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
struct AssetManager {
    db_path: String,
    page_size: i64,
    last_error: godot::global::Error,
    preview_file_names: Vec<String>,
    use_first_image: bool,
    use_folder_name: bool,

    #[allow(dead_code)]
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for AssetManager {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            db_path: String::new(),
            page_size: 50,
            last_error: godot::global::Error::OK,
            preview_file_names: vec!["Preview".to_string(), "Asset".to_string()],
            use_first_image: false,
            use_folder_name: true,
            base,
        }
    }
}

struct AssetManagerExtension;

#[gdextension]
unsafe impl ExtensionLibrary for AssetManagerExtension {}

#[godot_api]
impl AssetManager {
    /// Initialize a new AssetManager with a SQLite database.
    ///
    /// The database will be created if it doesn't exist. Creates tables for assets and deleted paths.
    ///
    /// [param db_path]: [String] Path to the SQLite database file (e.g. "user://assets.db")
    /// [br][br][b]Returns:[/b] [AssetManager] A new AssetManager instance
    /// [br][br]Example:
    /// [codeblock]
    /// var manager = AssetManager.new_db("user://assets.db")
    /// [/codeblock]
    #[func]
    fn new_db(db_path: GString) -> Gd<Self> {
        // Convert Godot path (user://, res://, etc.) to real filesystem path
        let real_path = if db_path.to_string().starts_with("user://") ||
                          db_path.to_string().starts_with("res://") {
            ProjectSettings::singleton()
                .globalize_path(&db_path)
                .to_string()
        } else {
            db_path.to_string()
        };

        let mut instance = Gd::from_init_fn(|base| {
            Self {
                db_path: real_path,
                page_size: 50,
                last_error: godot::global::Error::OK,
                preview_file_names: vec!["Preview".to_string(), "Asset".to_string()],
                use_first_image: false,
                use_folder_name: true,
                base,
            }
        });

        // Initialize database
        let init_result = instance.bind_mut().init_database();
        if let Err(e) = init_result {
            godot_error!("Failed to initialize database: {}", e);
            instance.bind_mut().last_error = godot::global::Error::ERR_CANT_CREATE;
        }

        instance
    }

    /// Set the maximum number of assets returned per page.
    ///
    /// This prevents out-of-memory errors when retrieving large numbers of assets.
    /// Minimum value is 1.
    ///
    /// [param size]: [int] Maximum assets per page (minimum 1)
    /// [br][br]Example:
    /// [codeblock]
    /// manager.set_page_size(100)
    /// [/codeblock]
    #[func]
    fn set_page_size(&mut self, size: i64) {
        self.page_size = size.max(1);
    }

    /// Get the current page size.
    ///
    /// [b]Returns:[/b] [int] Current maximum number of assets per page
    /// [br][br]Example:
    /// [codeblock]
    /// var size = manager.get_page_size()
    /// print("Page size: ", size)
    /// [/codeblock]
    #[func]
    fn get_page_size(&self) -> i64 {
        self.page_size
    }

    /// Set the preview file names to search for when discovering assets.
    ///
    /// When scanning directories without Asset.json, looks for images with these base names.
    /// Supports both literal names and regex patterns. Also checks folder name as a fallback.
    /// [br][br]
    /// Do not include file extensions - all supported image formats are automatically checked.
    /// [br]
    /// Patterns are treated as regex ONLY if they start with ^ (anchor).
    /// Otherwise treated as exact literal match (case-insensitive).
    /// [br]
    /// Literal patterns match the filename stem exactly (without extension), case-insensitive.
    /// Regex patterns have full control - use (?i) prefix for case-insensitive matching if desired.
    /// Regex results are still filtered for supported image extensions.
    ///
    /// [param file_names]: [Array] Array of filenames (without extensions) or regex patterns (e.g. ["Preview", "^(?i)thumb.*"])
    /// [br][br]Examples:
    /// [codeblock]
    /// # Literal exact match (case-insensitive: matches Preview.png, preview.jpg, PREVIEW.webp but NOT Preview1)
    /// manager.set_preview_file_names(["Preview", "Asset", "Thumbnail"])
    /// [br]
    /// # Regex patterns (must start with ^, use (?i) for case-insensitive)
    /// manager.set_preview_file_names(["^(?i)preview.*", "^thumb(nail)?.*", "^.*_00"])
    /// [/codeblock]
    #[func]
    fn set_preview_file_names(&mut self, file_names: Array<GString>) {
        self.preview_file_names = file_names.iter_shared()
            .map(|s| s.to_string())
            .collect();
    }

    /// Set whether to use the first image found if no specific preview file is found.
    ///
    /// When true, if none of the preview file names are found, uses the first image file
    /// with a supported extension (png, jpg, etc.).
    ///
    /// [param use_first]: [bool] Whether to use first image found as fallback
    /// [br][br]Example:
    /// [codeblock]
    /// manager.set_use_first_image(true)
    /// [/codeblock]
    #[func]
    fn set_use_first_image(&mut self, use_first: bool) {
        self.use_first_image = use_first;
    }

    /// Set whether to use the folder name as a fallback for finding preview images.
    ///
    /// When true, if none of the preview file names match, the scanner will look for
    /// an image file that matches the folder name (e.g., folder "MyAsset" looks for "MyAsset.png").
    /// This check happens before the first image fallback.
    ///
    /// [param use_folder]: [bool] Whether to use folder name as fallback
    /// [br][br]Example:
    /// [codeblock]
    /// manager.set_use_folder_name(true)
    /// [/codeblock]
    #[func]
    fn set_use_folder_name(&mut self, use_folder: bool) {
        self.use_folder_name = use_folder;
    }

    /// Get the total number of pages based on current page size.
    ///
    /// Calculates total pages by dividing total asset count by page size.
    ///
    /// [b]Returns:[/b] [int] Total number of pages
    /// [br][br]Example:
    /// [codeblock]
    /// var total_pages = manager.get_pages()
    /// print("Total pages: ", total_pages)
    /// [/codeblock]
    #[func]
    fn get_pages(&self) -> i64 {
        match self.get_connection() {
            Ok(conn) => {
                let count: i64 = conn
                    .query_row("SELECT COUNT(*) FROM assets", [], |row| row.get(0))
                    .unwrap_or(0);

                (count + self.page_size - 1) / self.page_size
            }
            Err(_) => 0,
        }
    }

    /// Get the total number of assets in the database.
    ///
    /// [b]Returns:[/b] [int] Total count of all assets
    /// [br][br]Example:
    /// [codeblock]
    /// var count = manager.get_asset_count()
    /// print("Total assets: ", count)
    /// [/codeblock]
    #[func]
    fn get_asset_count(&self) -> i64 {
        match self.get_connection() {
            Ok(conn) => {
                conn.query_row("SELECT COUNT(*) FROM assets", [], |row| row.get(0))
                    .unwrap_or(0)
            }
            Err(_) => 0,
        }
    }

    /// Get the last error that occurred.
    ///
    /// [b]Returns:[/b] [Error] Error code from the last operation (OK if no error)
    /// [br][br]Example:
    /// [codeblock]
    /// var error = manager.get_error()
    /// if error != OK:
    ///     print("Error occurred: ", error)
    /// [/codeblock]
    #[func]
    fn get_error(&self) -> godot::global::Error {
        self.last_error
    }

    /// Scan a directory recursively to discover and add assets to the database.
    ///
    /// Discovers assets in two ways:
    /// 1. Directories containing an Asset.json file (reads metadata from JSON)
    /// 2. Directories containing supported image files (creates asset automatically)
    /// [br]
    /// Supported image formats: png, jpeg, jpg, bmp, tga, webp, svg
    /// [br]
    /// Skips paths that were previously deleted and marked with remember_deleted.
    ///
    /// [param path]: [String] Base directory path to scan (e.g. "res://assets/")
    /// [br][br]Example:
    /// [codeblock]
    /// manager.find_assets("res://assets/models/")
    /// if manager.get_error() != OK:
    ///     print("Failed to scan directory")
    /// [/codeblock]
    #[func]
    fn find_assets(&mut self, path: GString) {
        self.last_error = godot::global::Error::OK;

        // Convert Godot path to real filesystem path
        let real_path = if path.to_string().starts_with("user://") ||
                          path.to_string().starts_with("res://") {
            ProjectSettings::singleton()
                .globalize_path(&path)
                .to_string()
        } else {
            path.to_string()
        };

        if let Err(e) = self.scan_directory(real_path) {
            godot_error!("Error finding assets: {}", e);
            self.last_error = godot::global::Error::ERR_FILE_CANT_READ;
        }
    }

    /// Add a new asset to the database manually.
    ///
    /// Creates a new asset entry with the specified metadata. The path must be unique.
    ///
    /// [param name]: [String] Display name of the asset
    /// [br][param path]: [String] Unique file system path to the asset directory
    /// [br][param image_path]: [String] Path to preview image (empty string if none)
    /// [br][param tags]: [Array] Array of string tags for categorization
    /// [br][br][b]Returns:[/b] [int] Asset ID on success, -1 on failure
    /// [br][br]Example:
    /// [codeblock]
    /// var tags = ["character", "fantasy"]
    /// var id = manager.add_asset("Wizard", "res://assets/wizard/", "res://assets/wizard/preview.png", tags)
    /// [br]
    /// if id == -1:[br]
    ///     print("Failed to add asset")
    /// [/codeblock]
    #[func]
    fn add_asset(&mut self, name: GString, path: GString, image_path: GString, tags: Array<GString>) -> i64 {
        self.last_error = godot::global::Error::OK;

        let tags_vec: Vec<String> = tags.iter_shared().map(|s| s.to_string()).collect();
        let img_path = if image_path.is_empty() {
            None
        } else {
            Some(image_path.to_string())
        };

        match self.insert_asset(&name.to_string(), &path.to_string(), img_path.as_deref(), &tags_vec) {
            Ok(id) => id,
            Err(e) => {
                godot_error!("Failed to add asset: {}", e);
                self.last_error = godot::global::Error::ERR_CANT_CREATE;
                -1
            }
        }
    }

    /// Get a single asset by its ID.
    ///
    /// [param id]: [int] The unique asset ID
    /// [br][br][b]Returns:[/b] [Dictionary] Asset dictionary with keys: name, path, image_path, tags
    /// [br]If asset not found or error occurs, returns dictionary with "error" key
    /// [br][br]Example:
    /// [codeblock]
    /// var asset = manager.get_asset(42)
    /// if asset.has("error"):
    ///     print("Asset not found")
    /// else:
    ///     print("Asset name: ", asset.name)
    ///     print("Asset path: ", asset.path)
    /// [/codeblock]
    #[func]
    fn get_asset(&mut self, id: i64) -> VarDictionary {
        self.last_error = godot::global::Error::OK;

        match self.fetch_asset(id) {
            Ok(Some(asset)) => self.asset_to_dict(&asset),
            Ok(None) => {
                self.last_error = godot::global::Error::ERR_DOES_NOT_EXIST;
                let mut dict = VarDictionary::new();
                dict.set("error", "Asset not found");
                dict
            }
            Err(e) => {
                godot_error!("Failed to get asset: {}", e);
                self.last_error = godot::global::Error::ERR_DATABASE_CANT_READ;
                let mut dict = VarDictionary::new();
                dict.set("error", e.to_string());
                dict
            }
        }
    }

    /// Get a page of assets from the database.
    ///
    /// Retrieves assets sorted by name with pagination support.
    /// Page numbers start at 1.
    ///
    /// [param page]: [int] Page number to retrieve (minimum 1)
    /// [br][br][b]Returns:[/b] [Dictionary] Dictionary with keys:
    /// [br]- page_number: Current page number
    /// [br]- page_size: Assets per page
    /// [br]- num_of_pages: Total number of pages
    /// [br]- assets: Array of asset dictionaries
    /// [br][br]Example:
    /// [codeblock]
    /// var result = manager.get_assets(1)
    /// print("Page ", result.page_number, " of ", result.num_of_pages)
    /// for asset in result.assets:
    ///     print(asset.name)
    /// [/codeblock]
    #[func]
    fn get_assets(&mut self, page: i64) -> VarDictionary {
        self.last_error = godot::global::Error::OK;

        let page = page.max(1);
        let offset = (page - 1) * self.page_size;

        match self.fetch_assets_page(offset, self.page_size) {
            Ok(assets) => {
                let mut dict = VarDictionary::new();
                dict.set("page_number", page);
                dict.set("page_size", self.page_size);
                dict.set("num_of_pages", self.get_pages());

                let mut assets_array = VarArray::new();
                for asset in &assets {
                    assets_array.push(&self.asset_to_dict(asset).to_variant());
                }
                dict.set("assets", assets_array);
                dict
            }
            Err(e) => {
                godot_error!("Failed to get assets: {}", e);
                self.last_error = godot::global::Error::ERR_DATABASE_CANT_READ;
                VarDictionary::new()
            }
        }
    }

    /// Update specific fields of an existing asset.
    ///
    /// Only updates fields present in the data dictionary. Other fields remain unchanged.
    /// Valid keys: "name", "path", "image_path", "tags"
    ///
    /// [param id]: [int] The asset ID to update
    /// [br][param data]: [Dictionary] Dictionary containing fields to update
    /// [br][br][b]Returns:[/b] [Error] OK on success, error code on failure
    /// [br][br]Example:
    /// [codeblock]
    /// var updates = {
    ///     "name": "Updated Name",
    ///     "tags": ["new_tag", "updated"]
    /// }
    /// var error = manager.update_asset(42, updates)
    /// if error != OK:
    ///     print("Update failed")
    /// [/codeblock]
    #[func]
    fn update_asset(&mut self, id: i64, data: VarDictionary) -> godot::global::Error {
        self.last_error = godot::global::Error::OK;

        if data.is_empty() {
            self.last_error = godot::global::Error::ERR_INVALID_DATA;
            return self.last_error;
        }

        let mut valid_keys = 0;
        let mut name: Option<String> = None;
        let mut path: Option<String> = None;
        let mut image_path: Option<Option<String>> = None;
        let mut tags: Option<Vec<String>> = None;

        for key in data.keys_array().iter_shared() {
            let key_str = key.to_string();
            match key_str.as_str() {
                "name" => {
                    if let Some(val) = data.get(key) {
                        name = Some(val.to_string());
                        valid_keys += 1;
                    }
                }
                "path" => {
                    if let Some(val) = data.get(key) {
                        path = Some(val.to_string());
                        valid_keys += 1;
                    }
                }
                "image_path" => {
                    if let Some(val) = data.get(key) {
                        let val_str = val.to_string();
                        image_path = Some(if val_str.is_empty() { None } else { Some(val_str) });
                        valid_keys += 1;
                    }
                }
                "tags" => {
                    if let Some(val) = data.get(key) {
                        if let Ok(arr) = val.try_to::<Array<GString>>() {
                            tags = Some(arr.iter_shared().map(|s| s.to_string()).collect());
                            valid_keys += 1;
                        }
                    }
                }
                _ => {}
            }
        }

        if valid_keys == 0 {
            self.last_error = godot::global::Error::ERR_INVALID_DATA;
            return self.last_error;
        }

        match self.update_asset_fields(id, name.as_deref(), path.as_deref(), image_path.as_ref().and_then(|o| o.as_deref()), tags.as_deref()) {
            Ok(_) => godot::global::Error::OK,
            Err(e) => {
                godot_error!("Failed to update asset: {}", e);
                self.last_error = godot::global::Error::ERR_DATABASE_CANT_WRITE;
                self.last_error
            }
        }
    }

    /// Delete an asset from the database.
    ///
    /// Optionally remembers the deleted path to prevent re-discovery during future scans.
    ///
    /// [param id]: [int] The asset ID to delete
    /// [br][param remember_deleted]: [bool] If true, marks the path as deleted to skip it in find_assets()
    /// [br][br][b]Returns:[/b] [Error] OK on success, error code on failure
    /// [br][br]Example:
    /// [codeblock]
    /// # Delete and remember to avoid re-adding
    /// var error = manager.delete_asset(42, true)
    /// if error == OK:
    ///     print("Asset deleted")
    /// [/codeblock]
    #[func]
    fn delete_asset(&mut self, id: i64, remember_deleted: bool) -> godot::global::Error {
        self.last_error = godot::global::Error::OK;

        let path = if remember_deleted {
            match self.fetch_asset(id) {
                Ok(Some(asset)) => Some(asset.path),
                _ => None,
            }
        } else {
            None
        };

        match self.remove_asset(id) {
            Ok(_) => {
                if let Some(p) = path {
                    if let Err(e) = self.mark_deleted(&p) {
                        godot_error!("Failed to mark as deleted: {}", e);
                    }
                }
                godot::global::Error::OK
            }
            Err(e) => {
                godot_error!("Failed to delete asset: {}", e);
                self.last_error = godot::global::Error::ERR_DATABASE_CANT_WRITE;
                self.last_error
            }
        }
    }

    /// Search for assets matching a query string.
    ///
    /// Searches in asset names, paths, and tags. Results are paginated like get_assets().
    /// Case-insensitive partial matching is used (LIKE %query%).
    ///
    /// [param query]: [String] Search string to match against
    /// [br][param page]: [int] Page number of results (minimum 1)
    /// [br][br][b]Returns:[/b] [Dictionary] Dictionary with keys:
    /// [br]- page_number: Current page number
    /// [br]- page_size: Assets per page
    /// [br]- num_of_pages: Total pages for this search
    /// [br]- assets: Array of matching asset dictionaries
    /// [br][br]Example:
    /// [codeblock]
    /// var results = manager.search("wizard", 1)
    /// print("Found ", results.assets.size(), " results")
    /// for asset in results.assets:
    ///     print("Match: ", asset.name)
    /// [/codeblock]
    #[func]
    fn search(&mut self, query: GString, page: i64) -> VarDictionary {
        self.last_error = godot::global::Error::OK;

        let page = page.max(1);
        let offset = (page - 1) * self.page_size;

        match self.search_assets(&query.to_string(), offset, self.page_size) {
            Ok((assets, total_count)) => {
                let mut dict = VarDictionary::new();
                dict.set("page_number", page);
                dict.set("page_size", self.page_size);
                dict.set("num_of_pages", (total_count + self.page_size - 1) / self.page_size);

                let mut assets_array = VarArray::new();
                for asset in &assets {
                    assets_array.push(&self.asset_to_dict(asset).to_variant());
                }
                dict.set("assets", assets_array);
                dict
            }
            Err(e) => {
                godot_error!("Failed to search assets: {}", e);
                self.last_error = godot::global::Error::ERR_DATABASE_CANT_READ;
                VarDictionary::new()
            }
        }
    }

    /// Flush any pending database changes to disk.
    ///
    /// Note: With SQLite, changes are committed immediately by default.
    /// This function exists for API compatibility with the original GDScript implementation.
    /// [br][br]Example:
    /// [codeblock]
    /// manager.flush()
    /// [/codeblock]
    #[func]
    fn flush(&mut self) {
        // With rusqlite, changes are committed immediately by default
        // This function is here for API compatibility
    }

    /// Clean up and close the database connection.
    ///
    /// Note: The database connection is automatically closed when the AssetManager is freed.
    /// This function exists for API compatibility with the original GDScript implementation.
    /// [br][br]Example:
    /// [codeblock]
    /// manager.quit()
    /// [/codeblock]
    #[func]
    fn quit(&mut self) {
        // Cleanup if needed
        // Connection will be closed when dropped
    }

    // Helper methods (not exposed to GDScript)

    fn get_connection(&self) -> SqlResult<Connection> {
        Connection::open(&self.db_path)
    }

    fn init_database(&self) -> SqlResult<()> {
        let conn = self.get_connection()?;

        conn.execute(
            "CREATE TABLE IF NOT EXISTS assets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                path TEXT NOT NULL UNIQUE,
                image_path TEXT,
                tags TEXT
            )",
            [],
        )?;

        conn.execute(
            "CREATE TABLE IF NOT EXISTS deleted (
                path TEXT PRIMARY KEY
            )",
            [],
        )?;

        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_assets_name ON assets(name)",
            [],
        )?;

        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_assets_path ON assets(path)",
            [],
        )?;

        // Migration: Add tags column if it doesn't exist (for existing databases)
        let has_tags = conn.query_row(
            "SELECT COUNT(*) FROM pragma_table_info('assets') WHERE name='tags'",
            [],
            |row| row.get::<_, i64>(0),
        ).unwrap_or(0);

        if has_tags == 0 {
            conn.execute("ALTER TABLE assets ADD COLUMN tags TEXT DEFAULT '[]'", [])?;
            // Update existing NULL values to empty array
            conn.execute("UPDATE assets SET tags = '[]' WHERE tags IS NULL", [])?;
        }

        Ok(())
    }

    fn insert_asset(&self, name: &str, path: &str, image_path: Option<&str>, tags: &[String]) -> SqlResult<i64> {
        let conn = self.get_connection()?;
        let tags_json = serde_json::to_string(tags).unwrap_or_else(|_| "[]".to_string());

        conn.execute(
            "INSERT INTO assets (name, path, image_path, tags) VALUES (?1, ?2, ?3, ?4)",
            params![name, path, image_path, tags_json],
        )?;

        Ok(conn.last_insert_rowid())
    }

    fn fetch_asset(&self, id: i64) -> SqlResult<Option<AssetData>> {
        let conn = self.get_connection()?;

        let result = conn.query_row(
            "SELECT name, path, image_path, tags FROM assets WHERE id = ?1",
            params![id],
            |row| {
                let name: String = row.get(0)?;
                let path: String = row.get(1)?;
                let image_path: Option<String> = row.get(2)?;
                let tags_json: Option<String> = row.get(3)?;
                let tags: Vec<String> = tags_json
                    .and_then(|json| serde_json::from_str(&json).ok())
                    .unwrap_or_default();

                Ok(AssetData {
                    name,
                    path,
                    image_path,
                    tags,
                })
            },
        );

        match result {
            Ok(asset) => Ok(Some(asset)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e),
        }
    }

    fn fetch_assets_page(&self, offset: i64, limit: i64) -> SqlResult<Vec<AssetData>> {
        let conn = self.get_connection()?;
        let mut stmt = conn.prepare(
            "SELECT name, path, image_path, tags FROM assets ORDER BY name LIMIT ?1 OFFSET ?2"
        )?;

        let assets = stmt.query_map(params![limit, offset], |row| {
            let name: String = row.get(0)?;
            let path: String = row.get(1)?;
            let image_path: Option<String> = row.get(2)?;
            let tags_json: Option<String> = row.get(3)?;
            let tags: Vec<String> = tags_json
                .and_then(|json| serde_json::from_str(&json).ok())
                .unwrap_or_default();

            Ok(AssetData {
                name,
                path,
                image_path,
                tags,
            })
        })?;

        assets.collect()
    }

    fn update_asset_fields(
        &self,
        id: i64,
        name: Option<&str>,
        path: Option<&str>,
        image_path: Option<&str>,
        tags: Option<&[String]>,
    ) -> SqlResult<()> {
        let conn = self.get_connection()?;

        if let Some(n) = name {
            conn.execute("UPDATE assets SET name = ?1 WHERE id = ?2", params![n, id])?;
        }

        if let Some(p) = path {
            conn.execute("UPDATE assets SET path = ?1 WHERE id = ?2", params![p, id])?;
        }

        if let Some(img) = image_path {
            conn.execute("UPDATE assets SET image_path = ?1 WHERE id = ?2", params![img, id])?;
        }

        if let Some(t) = tags {
            let tags_json = serde_json::to_string(t).unwrap_or_else(|_| "[]".to_string());
            conn.execute("UPDATE assets SET tags = ?1 WHERE id = ?2", params![tags_json, id])?;
        }

        Ok(())
    }

    fn remove_asset(&self, id: i64) -> SqlResult<()> {
        let conn = self.get_connection()?;
        conn.execute("DELETE FROM assets WHERE id = ?1", params![id])?;
        Ok(())
    }

    fn mark_deleted(&self, path: &str) -> SqlResult<()> {
        let conn = self.get_connection()?;
        conn.execute("INSERT OR IGNORE INTO deleted (path) VALUES (?1)", params![path])?;
        Ok(())
    }

    fn is_deleted(&self, path: &str) -> bool {
        let conn = match self.get_connection() {
            Ok(c) => c,
            Err(_) => return false,
        };

        let result: Result<i64, _> = conn.query_row(
            "SELECT 1 FROM deleted WHERE path = ?1",
            params![path],
            |row| row.get(0),
        );

        result.is_ok()
    }

    fn path_exists_in_db(&self, path: &str) -> bool {
        let conn = match self.get_connection() {
            Ok(c) => c,
            Err(_) => return false,
        };

        let result: Result<i64, _> = conn.query_row(
            "SELECT 1 FROM assets WHERE path = ?1",
            params![path],
            |row| row.get(0),
        );

        result.is_ok()
    }

    fn search_assets(&self, query: &str, offset: i64, limit: i64) -> SqlResult<(Vec<AssetData>, i64)> {
        let conn = self.get_connection()?;
        let search_pattern = format!("%{}%", query);

        let total_count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM assets WHERE name LIKE ?1 OR path LIKE ?1 OR tags LIKE ?1",
            params![&search_pattern],
            |row| row.get(0),
        )?;

        let mut stmt = conn.prepare(
            "SELECT name, path, image_path, tags FROM assets
             WHERE name LIKE ?1 OR path LIKE ?1 OR tags LIKE ?1
             ORDER BY name LIMIT ?2 OFFSET ?3"
        )?;

        let assets = stmt.query_map(params![&search_pattern, limit, offset], |row| {
            let name: String = row.get(0)?;
            let path: String = row.get(1)?;
            let image_path: Option<String> = row.get(2)?;
            let tags_json: Option<String> = row.get(3)?;
            let tags: Vec<String> = tags_json
                .and_then(|json| serde_json::from_str(&json).ok())
                .unwrap_or_default();

            Ok(AssetData {
                name,
                path,
                image_path,
                tags,
            })
        })?;

        let assets_vec: SqlResult<Vec<AssetData>> = assets.collect();
        Ok((assets_vec?, total_count))
    }

    fn scan_directory(&self, base_path: String) -> SqlResult<()> {
        let file_extensions = vec!["png", "jpeg", "jpg", "bmp", "tga", "webp", "svg"];

        let mut walker = WalkDir::new(&base_path)
            .follow_links(false)
            .into_iter();

        while let Some(entry) = walker.next() {
            let entry = match entry {
                Ok(e) => e,
                Err(_) => continue,
            };

            let path = entry.path();

            if !path.is_dir() {
                continue;
            }

            let path_str = path.to_string_lossy().to_string();

            // Check if already deleted
            if self.is_deleted(&path_str) {
                walker.skip_current_dir();
                continue;
            }

            // Check if path already exists in database - skip to speed up rescanning
            if self.path_exists_in_db(&path_str) {
                walker.skip_current_dir();
                continue;
            }

            // Check for Asset.json
            let asset_json = path.join("Asset.json");
            let has_asset_json = asset_json.exists();

            if has_asset_json {
                if let Ok(content) = std::fs::read_to_string(&asset_json) {
                    // Try to parse, but if it's empty/invalid, we'll auto-fill it
                    let asset_json_data = serde_json::from_str::<AssetData>(&content).ok();

                    // If we successfully parsed and have both name and path, use it as-is
                    if let Some(ref data) = asset_json_data {
                        if !data.name.is_empty() && !data.path.is_empty() {
                            let _ = self.insert_asset(
                                &data.name,
                                &data.path,
                                data.image_path.as_deref(),
                                &data.tags,
                            );
                            walker.skip_current_dir();
                            continue;
                        }
                    }
                }
                // If we reach here, Asset.json exists but is empty/incomplete - will auto-fill below
            }

            // Look for preview image files
            let folder_name = path
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| "Unknown".to_string());

            let mut found_image: Option<String> = None;
            let mut first_image: Option<String> = None;

            if let Ok(entries) = std::fs::read_dir(path) {
                let files: Vec<_> = entries.filter_map(|e| e.ok()).collect();

                // First pass: look for specific preview file names (supports regex)
                for preview_pattern in &self.preview_file_names {
                    // Check if pattern is regex (starts with '^')
                    let is_regex = preview_pattern.starts_with('^');

                    if is_regex {
                        // Use regex matching - user has full control (use (?i) in pattern for case-insensitive)
                        if let Ok(re) = Regex::new(&preview_pattern) {
                            for file_entry in &files {
                                let filename = file_entry.file_name().to_string_lossy().to_string();
                                if re.is_match(&filename) {
                                    // Verify it's an image file
                                    if let Some(ext) = file_entry.path().extension() {
                                        let ext_str = ext.to_string_lossy().to_lowercase();
                                        if file_extensions.contains(&ext_str.as_str()) {
                                            found_image = Some(file_entry.path().to_string_lossy().to_string());
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        // Use literal matching - exact filename match (case-insensitive)
                        // "Preview" matches "Preview.png", "preview.jpg" but NOT "Preview1.png"
                        for file_entry in &files {
                            if let Some(stem) = file_entry.path().file_stem() {
                                let stem_str = stem.to_string_lossy().to_string();

                                // Match if stem equals the pattern exactly (case-insensitive)
                                if stem_str.eq_ignore_ascii_case(&preview_pattern) {
                                    // Verify it's an image file
                                    if let Some(ext) = file_entry.path().extension() {
                                        let ext_str = ext.to_string_lossy().to_lowercase();
                                        if file_extensions.contains(&ext_str.as_str()) {
                                            found_image = Some(file_entry.path().to_string_lossy().to_string());
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if found_image.is_some() {
                        break;
                    }
                }

                // Second pass: look for folder name as filename (if enabled)
                if found_image.is_none() && self.use_folder_name {
                    for ext in &file_extensions {
                        let target_filename = format!("{}.{}", folder_name, ext);

                        if let Some(file_entry) = files.iter().find(|f| {
                            f.file_name().to_string_lossy().eq_ignore_ascii_case(&target_filename)
                        }) {
                            found_image = Some(file_entry.path().to_string_lossy().to_string());
                            break;
                        }
                    }
                }

                // Third pass: use first image if enabled OR if we have empty Asset.json
                if found_image.is_none() && (self.use_first_image || has_asset_json) {
                    for file_entry in &files {
                        if let Some(ext) = file_entry.path().extension() {
                            let ext_str = ext.to_string_lossy().to_lowercase();
                            if file_extensions.contains(&ext_str.as_str()) {
                                first_image = Some(file_entry.path().to_string_lossy().to_string());
                                break;
                            }
                        }
                    }
                }
            }

            // Insert asset if we found an image
            let final_image = found_image.or(first_image);

            // If we have an empty Asset.json file, write the auto-discovered data to it
            if has_asset_json {
                let auto_data = AssetData {
                    name: folder_name.clone(),
                    path: path_str.clone(),
                    image_path: final_image.clone().or(Some(String::new())),  // Empty string if no image found
                    tags: Vec::new(),
                };

                // Write the auto-discovered data to Asset.json
                if let Ok(json_content) = serde_json::to_string_pretty(&auto_data) {
                    let _ = std::fs::write(&asset_json, json_content);
                }
            }

            if let Some(image_path) = final_image {
                let _ = self.insert_asset(&folder_name, &path_str, Some(&image_path), &[]);
                // Skip subdirectories since we found an asset here
                walker.skip_current_dir();
            } else if has_asset_json {
                // Even without an image, if we had an empty Asset.json, skip subdirectories
                walker.skip_current_dir();
            }
        }

        Ok(())
    }

    fn asset_to_dict(&self, asset: &AssetData) -> VarDictionary {
        let mut dict = VarDictionary::new();
        dict.set("name", asset.name.clone());
        dict.set("path", asset.path.clone());

        if let Some(ref img_path) = asset.image_path {
            dict.set("image_path", img_path.clone());
        } else {
            dict.set("image_path", "");
        }

        let mut tags_array = VarArray::new();
        for tag in &asset.tags {
            tags_array.push(&GString::from(tag.as_str()).to_variant());
        }
        dict.set("tags", tags_array);

        dict
    }
}
