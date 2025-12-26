## Local assets browser 
An asset browser for local assets  
![image](https://github.com/user-attachments/assets/a164789c-62c1-4cf3-8356-e3045b08b0be)


## Usage
1. Click the folder icon in the top right and select the folder that all your assets are in.  
2. Wait for all the assets to appear.  
3. Find the asset you want and click `import`.  
4. The assets will be in `res://Assets/{asset_name}`.  
<!--
> [!CAUTION]  
> Currently loading hundreds of gigabytes of assets may crash the editor.  
> A fix is in the works.--> 

## Asset Discovery
The addon uses a Rust GDExtension with SQLite database for fast asset management. Assets are discovered by:

1. **Asset.json files** - Explicitly define an asset with metadata (name, path, preview image, tags)
2. **Preview file names** - Searches for images matching configured patterns (supports regex)
3. **Folder name matching** - If enabled, falls back to using the folder name (e.g., folder "MyAsset" looks for "MyAsset.png")
4. **First image fallback** - If enabled, uses the first image in a directory when no preview matches

When a directory contains an asset, subdirectories are skipped to avoid nested assets.

## Settings
| Editor Setting | Description |
| -------- | ------- |
| `Local_Assets/asset_dir` | Directory to look for the assets. Mainly used to keep the same directory across projects.  |
| `Local_Assets/File_preview_names` | An array of preview filename patterns (do not include file extensions - they're automatically checked). Literal names like `"Preview"` match exactly that filename (case-insensitive). Regex patterns starting with `^` allow flexible matching with full regex control (e.g., `"^(?i)preview.*"` for case-insensitive, `"^.*_00"` for case-sensitive). All supported image formats (png, jpg, webp, etc.) are automatically checked.  |
| `Local_Assets/use_folder_name` | If no preview pattern matches, look for an image file matching the folder name (default: true). For example, folder "MyAsset" will look for "MyAsset.png", "MyAsset.jpg", etc.  |
| `Local_Assets/use_first_image_found` | If no preview pattern or folder name matches, use the first image file found (default: false).  |
| `Local_Assets/page_size` | Number of assets to load per page (default: 50). Adjust for performance vs. convenience.  |
| `Local_Assets/use_uniform_image_size` | Force all images to be a uniform size.  |
| `Local_Assets/uniform_image_size` | Overrides all image sizes. Requires `Local_Assets/use_uniform_image_size` to be on.  |  

## Troubleshooting

### Assets Don't Show Up
If assets don't appear, the addon may not be finding matching preview images. Solutions:

1. **Add preview file patterns** in `EditorSettings -> Local_Assets -> File_preview_names`:
   - Exact literal names (no extension needed, case-insensitive): `["Preview", "Thumbnail", "Asset"]` - matches Preview.png, preview.jpg, etc. but NOT Preview1 or Preview_alt
   - Regex patterns (must start with `^`, no extension needed):
     - Case-insensitive: `["^(?i)preview.*", "^(?i)thumb(nail)?.*"]` - matches Preview1.png, THUMBNAIL_alt.jpg, etc.
     - Case-sensitive: `["^.*_00", "^car_.*"]` - matches car_00.webp but NOT CAR_00.png

2. **Enable folder name matching** in `EditorSettings -> Local_Assets -> use_folder_name` (enabled by default)

3. **Enable first image fallback** in `EditorSettings -> Local_Assets -> use_first_image_found`

4. **Create an Asset.json file** in the asset folder to explicitly define it:
   ```json
   {
     "path": "/path/to/asset/files",
     "name": "My Asset Name",
     "image_path": "/path/to/preview.png",
     "tags": ["2D", "platformer", "sprites"]
   }
   ```

   Required properties:
   - `path` - Base path for the asset (everything in this directory will be copied)
   - `name` - Asset name displayed in the browser

   Optional properties:
   - `image_path` - Custom preview image path
   - `tags` - Array of tag strings for searching/filtering

   ![image](https://github.com/user-attachments/assets/c9040acc-1450-4535-83f5-4acae19137dc)

### Database Issues
The addon uses an SQLite database (`<EditorDataFolder>/local_assets.db`) to cache asset information. If you experience issues:

1. **Reset the database** using the command palette: `Ctrl+Shift+P` → "Reset_db"
2. The database will be automatically recreated and assets rescanned

### Performance
- Adjust `Local_Assets/page_size` if loading many assets feels slow or you want to see more at once
- The database makes subsequent loads much faster than the initial scan


## Upcoming Features
 - Customizable install directory.

Have an idea? suggest it [here.](https://github.com/Kaifungamedev/godot_local_assets_browser/issues/new?assignees=&labels=&projects=&template=feature_request.md&title=)

## Known Issues
None. 😃
