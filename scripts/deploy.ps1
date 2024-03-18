$rbxcloudOutput = rbxcloud experience publish -f roblox-video-codec.rbxl -p ${{ vars.PLACE_ID }} -u ${{ vars.GAME_ID }} -t published -a 1020 2>&1

if ($rbxcloudOutput -notlike "*published * with version number*") {
    Write-Host "::error::$rbxcloudOutput"
    exit 1
}

#${{ secrets.DEPLOY_API_KEY }}
#rbxcloud assets update --asset-id ${{ vars.ASSET_ID }} --filepath roblox-video-codec.rbxm --api-key ${{ secrets.DEPLOY_API_KEY }} --asset-type model-fbx

$wallyOutput = wally login --token "${{secrets.WALLY_TOKEN}}" 2>&1
$wallyOutput += wally publish 2>&1
if ($wallyOutput -match "error") {
    Write-Host "::error::$wallyOutput"
    exit 1
}

Write-Host "Deployed Successfully."