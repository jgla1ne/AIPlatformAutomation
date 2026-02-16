#!/bin/bash
# Smart volume detection for mounting EBS volumes
set -euo pipefail

echo "🔍 DETECTING AVAILABLE VOLUMES..."

# Get list of available volumes (excluding system volumes)
echo "Available volumes:"
lsblk -d -o NAME,SIZE,MODEL | grep -E "nvme|xvd" | grep -v "loop" | while read -r device size model; do
    # Skip if already mounted
    if findmnt -rn -S "/dev/$device" >/dev/null 2>&1; then
        echo "❌ /dev/$device is already mounted"
        continue
    fi
    
    # Check if it's a data volume (not boot/system)
    size_gb=$(echo "$size" | sed 's/G//')
    if [[ "$size_gb" =~ ^[0-9]+$ ]] && [[ "$size_gb" -gt 50 ]]; then
        echo "✅ /dev/$device ($size) - AVAILABLE FOR MOUNTING"
        echo "   Model: $model"
        echo "   Suggested mount point: /mnt"
    fi
done

echo ""
echo "🎯 RECOMMENDED ACTIONS:"
echo "1. Select volume from list above"
echo "2. Mount to /mnt (or other preferred location)"
echo "3. Update /etc/fstab for persistence"
echo "4. Run Script 1 to configure with proper volume"
