## Local assets browser 
An asset browser for local assets  
![image](https://github.com/Kaifungamedev/godot_local_assets_browser/assets/110266485/69f9bdbc-34ab-4fbf-aa52-3bb2cf7f0a7c)  

## Usage
1. Click the folder icon in the top right and select the folder that all your assets are in.  
2. Wait for all the assets to appear.  
3. Find the asset you want and click `import`.  
4. The assets should be in `res://Assets/{asset_name}`.  

## Settings  
	`Local_Assets/asset_dir` - directory to look for the assets. mainly used to keep the same directory across projects
	`Local_Assets/File_preview_names` - An array of names for preview files. files must be images.  

## Troubleshooting  
My assets are not showing up -> this is probably caused by the addon can't find a file name that's found in its settings, you can add file names in the editor settings `Local_Assets/File_preview_names`.   
  If you don't have a preview file you can add a file named `Assets.json`. The `Assets.json` file must contain 2 properties   
	- `path` - the base path for the asset everything in here will be copied to your project  
	- `name` - the name of the asset that will appear in the browser  
	- (Optional) `image_path` - Preview image
![image](https://github.com/Kaifungamedev/godot_local_assets_browser/assets/110266485/71d9b5d4-f986-4e36-8547-bb60be1c3f54)
