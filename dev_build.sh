#! /bin/bash
echo "Building AssetManager addon for local_assets"
cd rust 
cargo build
echo "Copying built library to addon directory"
cp target/debug/libAssetManager.so ../addons/local_assets/bin/libAssetManager.linux.x86_64.so
echo "Build complete!"