## Local assets browser 
An asset browser for local assets  
![image](https://github.com/Kaifungamedev/godot_local_assets_browser/assets/110266485/69f9bdbc-34ab-4fbf-aa52-3bb2cf7f0a7c)  

## Usage
1. Click the folder icon in the top right and select the folder that all your assets are in.  
2. Wait for all the assets to appear.  
3. Find the asset you want and click `import`.  
4. The assets should be in `res://Assets/{asset_name}`.  
> [!CAUTION]  
> Currently loading hundreds of gigabytes of assets may crash the editor.  
> A fix is in the works. 

## Settings  
`Local_Assets/asset_dir` - directory to look for the assets. mainly used to keep the same directory across projects
`Local_Assets/File_preview_names` - An array of names for preview files. files must be images.  
`Local_Assets/use_first_image_found` - If a file in a does not match any name in `Local_Assets/File_preview_names` and no `Assets.json` file is found it will take the first image file it finds and use that.  
`Local_Assets/use_uniform_image_size` - force all images to be a uniform size.
`Local_Assets/uniform_image_size` - overrides all image sizes. Requires `Local_Assets/use_uniform_image_size` to be on.

## Troubleshooting  
1. If assets don't show up this could be because the addon looks for image files with a specific name if it can't find a file with that name it skips it. You can add file names in  `EditorSettings -> Local_Assets -> File_preview_names`.     
	Alternatively, you can force a directory to be an asset by putting a file named `Assets.json` in the folder you want to be an asset.  
	The `Assets.json` file must contain the following properties:  
		&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;- `path` - the base path for the asset everything in here will be copied to your project  
		&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;- `name` - the name of the asset that will appear in the browser  
		&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;- (Optional) `image_path` - Preview image
		&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;- (Optional) `taga` - asset tags
	![image](https://github.com/Kaifungamedev/godot_local_assets_browser/assets/110266485/71d9b5d4-f986-4e36-8547-bb60be1c3f54)
