rbxcloud experience publish -f roblox-video-codec.rbxl -p ${env:PLACE_ID} -u ${env:GAME_ID} -t published -a 1010 #${env:DEPLOY_API_KEY}

#rbxcloud assets update --asset-id ${{ vars.ASSET_ID }} --filepath roblox-video-codec.rbxm --api-key ${{ secrets.DEPLOY_API_KEY }} --asset-type model-fbx

wally login --token ${env:WALLY_TOKEN}
wally publish

Write-Host "Deployed Successfully."
